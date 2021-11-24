#!/usr/bin/env python3

# Install FreeBSD
# Copyright (c) 2020-21, Simon Peter <probono@puredarwin.org>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


import sys
import os
import re
import socket
import shutil
import subprocess
from datetime import datetime
import urllib.request
import urllib.error
import json
from PyQt5 import QtWidgets, QtGui, QtCore, QtMultimedia # pkg install py37-qt5-widgets
# PySide2 wants to install 1 GB whereas PyQt5 only needs 40 MB installed on FuryBSD XFCE
# from PyQt5 import QtMultimedia # pkg install  py37-qt5-multimedia
# QtMultimedia is used for playing the success sound; using mpg123 for now instead

import disks  # Privately bundled file

import ssl

# Translate this application using Qt .ts files without the need for compilation
import tstranslator
# FIXME: Do not import translations from outside of the appliction bundle
# which currently is difficult because we have all translations for all applications
# in the whole repository in the same .ts files
tstr = tstranslator.TsTranslator(os.path.dirname(__file__) + "/i18n", "")
def tr(input):
    return tstr.tr(input)


# Since we are running the installer on Live systems which more likely than not may have
# the clock wrong, we cannot verify SSL certificates. Setting the following allows
# content to be fetched from https locations even if the SSL certification cannot be verified.
# This is needed, e.g., for geolocation.
ssl._create_default_https_context = ssl._create_unverified_context

# Plenty of TODOs and FIXMEs are sprinkled across this code.
# These are invitations for new contributors to implement or comment on how to best implement.
# These things are not necessarily hard, just no one had the time to do them so far.
# TODO: Make it possible to clone an already-installed system to another one (backup) (skip rootpw, username screens)
# TODO: Make live system clonable in live mode (just clone the live media as-is)
# TODO: Make live system writable to DVD
# TODO: Make installed system behave like live system if the user so desires (skip rootpw, username screens)


#############################################################################
# Helper functions
#############################################################################


def details():
    print("Details clicked")


#############################################################################
# Initialization
# https://doc.qt.io/qt-5/qwizard.html
#############################################################################

print(tr("Install FreeBSD"))

app = QtWidgets.QApplication(sys.argv)


class InstallWizard(QtWidgets.QWizard, object):
    def __init__(self):

        print("Preparing wizard")
        super().__init__()

        self.required_mib_on_disk = 0
        self.installer_script = "developer-install.sh"
        
        self.selected_vol = None

        # For any external binaries, prefer those that are in the same directory as this file.
        # This can be used to ship a newer installer shell script alongside the installer if needed.
        if os.path.exists(os.path.dirname(__file__) + "/" + self.installer_script):
            self.installer_script = os.path.dirname(__file__) + "/" + self.installer_script

        # TODO: Make sure it is actually executable

        self.should_show_last_page = False
        self.error_message_nice = tr("An unknown error occured.")

        self.setWizardStyle(QtWidgets.QWizard.MacStyle)

        # self.setButtonLayout(
        #     [QtWidgets.QWizard.CustomButton1, QtWidgets.QWizard.Stretch, QtWidgets.QWizard.NextButton])

        self.setWindowTitle(tr("Install Developer Tools"))
        self.setFixedSize(800, 550)

        # Remove window decorations, especially the close button
        self.setWindowFlags(QtCore.Qt.CustomizeWindowHint)
        self.setWindowFlags(QtCore.Qt.FramelessWindowHint)

        self.setPixmap(QtWidgets.QWizard.BackgroundPixmap, QtGui.QPixmap(os.path.dirname(__file__) + '/Background.png'))

        self.setOption(QtWidgets.QWizard.ExtendedWatermarkPixmap, True)
        # self.setPixmap(QtWidgets.QWizard.LogoPixmap, 'Logo.png')
        # self.setPixmap(QtWidgets.QWizard.BannerPixmap, 'Banner.png')

        # Create empty Installer Log files
        # TODO: Catch errors and send to errors page
        self.logfile = "/tmp/Installer.log"
        self.errorslogfile = "/tmp/Installer.err"
        for f in [self.logfile, self.errorslogfile]:
            if os.path.exists(f):
                os.remove(f)
                print(tr("Pre-existing %s removed") % (f))
            file = open(f, "w")
            file.write(datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
            file.close()
        # TODO: Redirect own output to those files?

        # Add Installer Log button
        self.setOption(QtWidgets.QWizard.HaveCustomButton1)
        self.setButtonText(self.CustomButton1, tr("Installer Log"))
        self.customButtonClicked.connect(self.installerLogButtonClicked)

        # Translate the widgets in the UI objects in the Wizard
        self.setWindowTitle(tr(self.windowTitle()))
        for e in self.findChildren(QtCore.QObject, None, QtCore.Qt.FindChildrenRecursively):
            if hasattr(e, 'text') and hasattr(e, 'setText'):
                e.setText(tr(e.text()))
                
        self.progress = QtWidgets.QProgressBar(self)

    # TODO: Find a way to stream the output of an installer shell script
    # into a log window. Probably need to read the installer output line by line
    # and make sure it does not interfere with our progress bar (this may be tricky).
    # This would remove the xterm dependency, look nicer, and prevent multiple installer log windows from being opened
    # *** Actually seems easy: self.ext_process.readyReadStandardOutput.connect, https://stackoverflow.com/questions/12733479/python-pyqt-how-to-set-environment-variable-for-qprocess

    # As a simpler alternative for now, just touch /tmp/InstallerLog /tmp/InstallerLog.errors, then
    # launch the installer shell script with "> /tmp/InstallerLog 2>/tmp/InstallerLog.errors"
    # and check its exit code.
    # If the user clicks on "Installer Log", then simply open
    # xterm +sb -geometry 200x20  -e "tail -f /tmp/InstallerLog*"

    def installerLogButtonClicked(self):
        print("Showing Installer Log")
        proc = QtCore.QProcess()
        # command = 'xterm'
        # args = ['-T', 'Installer Log', '-n', 'Installer Log', '+sb', '-geometry', '200x20', '-e', 'tail', '-f', self.logfile, self.errorslogfile]
        command = 'launch'
        args = ['QTerminal', '-e', 'tail', '-f', self.logfile, self.errorslogfile]
        print(args)
        try:
            proc.startDetached(command, args)
        except:  # FIXME: do not use bare 'except'
            self.showErrorPage(tr("The Installer Log cannot be opened."))
            return

    def showErrorPage(self, message):
        print("Show error page")
        self.addPage(ErrorPage())
        # It is not possible jo directly jump to the last page from here, so we need to take a workaround
        self.should_show_last_page = True
        self.error_message_nice = message
        self.next()

    # When we are about to go to the next page, we need to check whether we have to show the error page instead
    def nextId(self):
        if self.should_show_last_page is True:
            return max(wizard.pageIds())
        else:
            return self.currentId() + 1

    def playSound(self):
        print("Playing sound")
        # https://freesound.org/people/Leszek_Szary/sounds/171670/, licensed under CC0
        soundfile = os.path.dirname(__file__) + '/success.mp3'
        if os.path.exists(soundfile):
            try:
                subprocess.run(["mpg321", soundfile], stdout=subprocess.PIPE, text=True)
            except:
                pass
        else:
            print("No sound available")

wizard = InstallWizard()

#############################################################################
# Intro page
#############################################################################

class IntroPage(QtWidgets.QWizardPage, object):
    def __init__(self):

        print("Preparing IntroPage")
        super().__init__()

        self.setTitle(tr('Install Developer Tools'))
        self.setSubTitle(tr("To install the Developer Tools, click 'Continue'."))

        # logo_pixmap = QtGui.QPixmap(os.path.dirname(__file__) + '/FREEBSD_Logo_Vert_Pos_RGB.png').scaledToHeight(200, QtCore.Qt.SmoothTransformation)
        # logo_label = QtWidgets.QLabel()
        # logo_label.setPixmap(logo_pixmap)

        # center_layout = QtWidgets.QHBoxLayout(self)
        # center_layout.addStretch()
        # center_layout.addWidget(logo_label)
        # center_layout.addStretch()

        # center_widget = QtWidgets.QWidget()
        # center_widget.setLayout(center_layout)
        intro_vLayout = QtWidgets.QVBoxLayout(self)
        # intro_vLayout.addWidget(center_widget, True)  # True = add stretch vertically

        intro_label = QtWidgets.QLabel()
        intro_label.setWordWrap(True)
        intro_label.setText(tr("Developer Tools contain compilers, header files, object code, and documentation."))
        intro_vLayout.addWidget(intro_label, True)  # True = add stretch vertically

        tm_label = QtWidgets.QLabel()
        tm_label.setWordWrap(True)
        font = wizard.font()
        font.setPointSize(8)
        tm_label.setFont(font)
        tm_label.setText("The FreeBSD Logo and the mark FreeBSD are registered trademarks of The FreeBSD Foundation and are used by Simon Peter with the permission of The FreeBSD Foundation.")
        intro_vLayout.addWidget(tm_label)


#############################################################################
# License
#############################################################################

class LicensePage(QtWidgets.QWizardPage, object):
    def __init__(self):

        print("Preparing LicensePage")
        super().__init__()

        self.setTitle(tr('License Terms'))
        self.setSubTitle(tr('To continue installing the software, you must agree to the terms of the software license agreement.'))
        license_label = QtWidgets.QLabel()
        license_label.setWordWrap(True)
        license_layout = QtWidgets.QVBoxLayout(self)
        license_text = open('/COPYRIGHT', 'r').read()
        license_label.setText("\n".join(license_text.split("\n")[3:]))  # Skip the first 3 lines

        font = wizard.font()
        font.setFamily("monospace")
        font.setPointSize(8)
        license_label.setFont(font)
        license_area = QtWidgets.QScrollArea()
        license_area.setWidget(license_label)
        license_layout.addWidget(license_area)

        additional_licenses_label = QtWidgets.QLabel()
        additional_licenses_label.setWordWrap(True)
        additional_licenses_label.setText(tr("Additional components may be distributed under different licenses as stated in the respective documentation."))
        license_layout.addWidget(additional_licenses_label)


#############################################################################
# Destination disk
#############################################################################

class DiskPage(QtWidgets.QWizardPage, object):
    def __init__(self):

        print("Preparing DiskPage")
        super().__init__()
        # We currently determine the required disk space by looking at the disk space needed by /
        # and multiplying by 1.3 as a safety measure; this may be too much?
        # NOTE: If the installer logic changes and the files are not copied from / but e.g., directly from an image
        # then the following line needs to be changed to reflect the changed logic accordingly

        self.timer = QtCore.QTimer()  # Used to periodically check the available disks
        self.old_vols = None  # The disks we have recognized so far
        self.setTitle(tr('Select Destination Disk'))
        self.setSubTitle(tr('Developer Tools will be installed on the selected disk.'))
        self.disk_listwidget = QtWidgets.QListWidget()
        # self.disk_listwidget.setViewMode(QtWidgets.QListView.IconMode)
        self.disk_listwidget.setIconSize(QtCore.QSize(48, 48))
        # self.disk_listwidget.setSpacing(24)

        disk_vlayout = QtWidgets.QVBoxLayout(self)
        disk_vlayout.addWidget(self.disk_listwidget)
        self.label = QtWidgets.QLabel()
        disk_vlayout.addWidget(self.label)

    def getMiBRequiredOnDisk(self):
        # _, space_used_on_root_mountpoint, _ = shutil.disk_usage("/")
        # return int(float(space_used_on_root_mountpoint * 1.3))
        proc = QtCore.QProcess()
        command = 'sudo'
        args = ["-n", "-E", wizard.installer_script]  # -E to pass environment variables into the command ran with sudo
        env = QtCore.QProcessEnvironment.systemEnvironment()
        env.insert("INSTALLER_PRINT_MIB_NEEDED", "YES")
        proc.setProcessEnvironment(env)
        try:
            print("Starting %s %s" % (command, args))
            proc.start(command, args)
        except:
            return 0
        proc.waitForFinished()
        output_lines = proc.readAllStandardOutput().split("\n")

        mib = 0
        for output_line in output_lines:
            print(str(output_line))
            if "INSTALLER_MIB_NEEDED=" in str(output_line):
                mib = int(output_line.split("=")[1])
                print("Response from the installer script: %i" % mib)
                correction_factor = 1.5  # FIXME: Correction factor due to compression differences
                adjusted_mib = int(mib * correction_factor)
                print("Adjusted MiB needed: %i" % adjusted_mib)
                return adjusted_mib
        return 0

    def initializePage(self):
        print("Displaying DiskPage")

        wizard.required_mib_on_disk = self.getMiBRequiredOnDisk()
        self.disk_listwidget.clearSelection()  # If the user clicked back and forth, start with nothing selected
        self.periodically_list_disks()
        
        self.disk_listwidget.itemSelectionChanged.connect(self.completeChanged)

        if wizard.required_mib_on_disk < 5:
            self.timer.stop()
            wizard.showErrorPage(tr("The installer script did not report the required disk space. Are you running the installer on a supported system? Can you run the installer script with sudo without needing a password?"))
            self.disk_listwidget.hide()  # FIXME: Why is this needed? Can we do without?
            return

        # Since we are installing to zfs with compression on, we will actually need less
        # space on the target disk. Hence we are using a correction factor derived from
        # experimentation here.
        zfs_compression_factor = 7984/2499 
        wizard.required_mib_on_disk = wizard.required_mib_on_disk / zfs_compression_factor

        print("Disk space required: %d MiB" % wizard.required_mib_on_disk)
        self.label.setText(tr("Disk space required: %s MiB") % wizard.required_mib_on_disk)

    def cleanupPage(self):
        print("Leaving DiskPage")

    def periodically_list_disks(self):
        print("periodically_list_disks called")
        self.list_disks()
        self.timer.setInterval(3000)
        self.timer.timeout.connect(self.list_disks)
        self.timer.start()


    def list_disks(self):
        vols = QtCore.QStorageInfo.mountedVolumes()
        
        # Do not refresh the list of disks if nothing has changed,
        # because it de-selects the selection
        if vols != self.old_vols:
            self.disk_listwidget.clear()
            for vol in vols:
                # print(vol.device().data().decode().replace("/dev/", ""))
                # print(vol.bytesTotal())
                # print(vol.bytesFree())
                # print(vol.isReadOnly())
                
                print("Start looking at %s" % vol.device().data().decode())
                
                # Filter out volumes we don't even want to show
                
                if vol.device().data().decode() == "tmpfs":
                    continue
                elif vol.device().data().decode() == "devfs":
                    continue
                elif vol.device().data().decode() == "fdescfs":
                    continue
                elif vol.device().data().decode() == "linprocfs":
                    continue
                elif vol.device().data().decode() == "linsysfs":
                    continue
                elif vol.device().data().decode().endswith("/tmp"):
                    continue
                elif vol.device().data().decode().endswith("/home"):
                    continue
                elif vol.device().data().decode().endswith("/ports"):
                    continue
                elif vol.device().data().decode().endswith("/src"):
                    continue
                elif vol.device().data().decode().endswith("/var/audit"):
                    continue
                elif vol.device().data().decode().endswith("/var/crash"):
                    continue
                elif vol.device().data().decode().endswith("/var/mail"):
                    continue
                elif vol.device().data().decode().endswith("/var/log"):
                    continue                
                elif vol.device().data().decode() == "/dev/fuse":
                    continue
                elif vol.device().data().decode().startswith("/media/.uzip"):
                    continue
                elif vol.device().data().decode().startswith("/tmp"):
                    continue
                elif vol.device().data().decode().startswith("<"):
                    # unionfs '<above>', '<below>'
                    continue
                                                     
                title = "%s (%s GiB)" % (vol.device().data().decode().replace("/dev/", ""), f"{(vol.bytesFree() // (2 ** 30)):,}")
                if vol.device().data().decode().replace("/dev/", "").startswith("cd") == True:
                    # TODO: Add burning powers
                    item = QtWidgets.QListWidgetItem(QtGui.QIcon.fromTheme('drive-optical'), title)
                elif vol.device().data().decode().replace("/dev/", "").startswith("da") == True:
                    item = QtWidgets.QListWidgetItem(QtGui.QIcon.fromTheme('drive-removable-media'), title)
                else:
                    item = QtWidgets.QListWidgetItem(QtGui.QIcon.fromTheme('drive-harddisk'), title)

                setattr(item, "vol", vol)

                self.disk_listwidget.addItem(item)

                # Filter out volumes we want to show but grayed out
                
                if vol.bytesFree() // 1024 // 1024 < wizard.required_mib_on_disk:
                    item.setFlags(QtCore.Qt.ItemIsSelectable) # Gray it out
                    item.setToolTip(tr("Not enough space on this volume"))

                if vol.device().data().decode().startswith("cd"):
                    item.setFlags(QtCore.Qt.ItemIsSelectable) # Gray it out
                    item.setToolTip(tr("Cannot install to optical media"))

                if not os.path.exists(vol.rootPath() + "/etc/os-release"):
                    # TODO: Also check that the version of the OS matches
                    # the version of Developer Utilities
                    # Can we use a comparison of creation times?
                    item.setFlags(QtCore.Qt.ItemIsSelectable) # Gray it out
                    item.setToolTip(tr("Volume does not contain an operating system"))

                # Get and display the disk name ("volume label")
                # and show it instead of the geom if possible
                result = subprocess.run(["blkid", "-s", "LABEL", "-o" ,"value", vol.device().data().decode()], capture_output=True)
                if result.returncode == 0:
                    vol_label = str(result.stdout.decode()).strip()
                    if vol_label != "":
                        print("Volume label: '%s'" % vol_label)
                        item.setText(tr("%s on %s") % (vol_label, title))
                else:
                    print("Could not determine volume label for %s" % title)
                    
                print("Done looking at %s" % vol.device().data().decode())
                    
            self.old_vols = vols
            
            print("Done with all")


    def isComplete(self):
        print("isComplete called to check whether we can proceed")
        # This needs
        # self.disk_listwidget.itemSelectionChanged.connect(self.completeChanged)
        # above to work
        # Check that we can get at the vol object of the selected item
        num_selected_items = len(self.disk_listwidget.selectedItems())
        if num_selected_items == 1:
            wizard.selected_vol = getattr(self.disk_listwidget.selectedItems()[0], "vol")
            return True
        else:
            # Nothing was selected yet
            wizard.selected_vol = None
            return False

#############################################################################
# Installation page
#############################################################################

class InstallationPage(QtWidgets.QWizardPage, object):
    def __init__(self):

        print("Preparing InstallationPage")
        super().__init__()

        self.setTitle(tr('Installing Developer Tools'))
        self.setSubTitle(tr('Developer Tools are being installed to your computer.'))

        self.timer = None
        self.installer_script_has_exited = False
        self.mib_used_on_target_disk = 0
        
        self.ext_process = QtCore.QProcess()

        self.layout = QtWidgets.QVBoxLayout(self)
        
        self.layout.addWidget(wizard.progress, True)

        # To update the progress bar, we need to know how much data is going to be copied
        # and we need to check how full the target disk is every few seconds

        # TODO: To estimate the remaining time, we could calculate the seconds since we started
        # and since we know the percentage copied, just extrapolate from there.
        # Should be about as accurate as other installers...

    def initializePage(self):
        print("Displaying InstallationPage")
        wizard.setButtonLayout(
            [QtWidgets.QWizard.CustomButton1, QtWidgets.QWizard.Stretch])
        bytes_already_on_disk_before_install = wizard.selected_vol.bytesTotal()
        print("bytes_already_on_disk_before_install: %i" % bytes_already_on_disk_before_install)
        self.mib_already_on_disk_before_install =  bytes_already_on_disk_before_install // 1024 // 1024
        print("self.mib_already_on_disk_before_install: %i" % self.mib_already_on_disk_before_install)
        print("wizard.required_mib_on_disk: %i" % wizard.required_mib_on_disk)

        wizard.progress.setRange(0, self.mib_already_on_disk_before_install + wizard.required_mib_on_disk)
        wizard.progress.setValue(0)

        # Sanity check that we really have a device
        if not wizard.selected_vol.bytesTotal():
            wizard.showErrorPage(tr("The selected disk device %s is not found.") % dev_file)
            return  # Stop doing anything here

        # Launch installer script

        command = "sudo"
        args = ["-n", "-E", wizard.installer_script]  # -E to pass environment variables into the command ran with sudo
        env = QtCore.QProcessEnvironment.systemEnvironment()
        
        env.insert("INSTALLER_TARGET_MOUNTPOINT", wizard.selected_vol.rootPath())
        
        print("xxxxxxxxxxxx1")

        self.ext_process.setProcessEnvironment(env)
        self.ext_process.setStandardOutputFile(wizard.logfile)
        self.ext_process.setStandardErrorFile(wizard.errorslogfile)
        self.ext_process.finished.connect(self.onProcessFinished)
        self.ext_process.setProgram(command)
        self.ext_process.setArguments(args)

        self.periodicallyCheckProgress()
        try:
            self.ext_process.start()
            # print(pid) # This is None for non-detached processes. If we ran detached, we would get the pid back here
            print("Installer script process %s %s started" % (command, args))
        except:  # FIXME: do not use bare 'except'
            self.showErrorPage(tr("The installer cannot be launched."))
            return  # Stop doing anything here

    def onProcessFinished(self):
        print("Installer script process finished")
        # cursor = self.output.textCursor()
        # cursor.movePosition(cursor.End)
        # cursor.insertText(str(self.ext_process.readAllStandardOutput()))
        # self.output.ensureCursorVisible()
        exit_code = self.ext_process.exitCode()
        print("Installer script exit code: %s" % exit_code)
        self.installer_script_has_exited = True
        self.timer.stop()
        if(exit_code != 0):
            wizard.showErrorPage(tr("The installation did not succeed. Please see the Installer Log for more information."))
            return  # Stop doing anything here
        else:
            wizard.next()

    def periodicallyCheckProgress(self):
        print("periodically_check_progress called")
        self.checkProgress()
        self.timer = QtCore.QTimer()  # Used to periodically check the fill level of the target disk
        self.timer.setInterval(200)
        self.timer.timeout.connect(self.checkProgress)
        self.timer.start()

    def checkProgress(self):
        # print("check_progress")
        # print("wizard.progress.value: %i", wizard.progress.value())
        used = wizard.selected_vol.bytesTotal()
        mib_used_on_target_disk = used // 1024 // 1024

        print("%i of %i MiB on target disk" % (self.mib_used_on_target_disk, wizard.required_mib_on_disk))

        if wizard.progress.value() > wizard.required_mib_on_disk + self.mib_already_on_disk_before_install:
            # The target disk is filled more than we thought we would need
            wizard.progress.setRange(0, 0) # Indeterminate
        else:
            wizard.progress.setRange(0, wizard.required_mib_on_disk + self.mib_already_on_disk_before_install)
            wizard.progress.setValue(mib_used_on_target_disk)
        
#############################################################################
# Success page
#############################################################################

class SuccessPage(QtWidgets.QWizardPage, object):
    def __init__(self):

        print("Preparing SuccessPage")
        super().__init__()

    def initializePage(self):
        print("Displaying SuccessPage")
        wizard.setButtonLayout(
            [QtWidgets.QWizard.CustomButton1, QtWidgets.QWizard.Stretch, QtWidgets.QWizard.CancelButton, QtWidgets.QWizard.NextButton])

        wizard.playSound()

        self.setTitle(tr('Installation Complete'))
        self.setSubTitle(tr('The installation succeeded.'))

        logo_pixmap = QtGui.QPixmap(os.path.dirname(__file__) + '/check.png').scaledToHeight(256, QtCore.Qt.SmoothTransformation)
        logo_label = QtWidgets.QLabel()
        logo_label.setPixmap(logo_pixmap)

        center_layout = QtWidgets.QHBoxLayout(self)
        center_layout.addStretch()
        center_layout.addWidget(logo_label)
        center_layout.addStretch()

        center_widget = QtWidgets.QWidget()
        center_widget.setLayout(center_layout)
        layout = QtWidgets.QVBoxLayout(self)
        layout.addWidget(center_widget, True)  # True = add stretch vertically

        label = QtWidgets.QLabel()
        label.setText(tr("Developer Tools have been installed on your computer."))
        layout.addWidget(label)

        self.setButtonText(wizard.NextButton, tr("Quit"))
        wizard.button(QtWidgets.QWizard.NextButton).clicked.connect(self.quit)

    def quit(self):
        sys.exit(0)


#############################################################################
# Error page
#############################################################################

class ErrorPage(QtWidgets.QWizardPage, object):
    def __init__(self):
        print("Preparing ErrorPage")
        super().__init__()

        self.setTitle(tr('Error'))
        self.setSubTitle(tr('The installation could not be performed.'))

        logo_pixmap = QtGui.QPixmap(os.path.dirname(__file__) + '/cross.png').scaledToHeight(256, QtCore.Qt.SmoothTransformation)
        logo_label = QtWidgets.QLabel()
        logo_label.setPixmap(logo_pixmap)

        center_layout = QtWidgets.QHBoxLayout(self)
        center_layout.addStretch()
        center_layout.addWidget(logo_label)
        center_layout.addStretch()

        center_widget = QtWidgets.QWidget()
        center_widget.setLayout(center_layout)
        self.layout = QtWidgets.QVBoxLayout(self)
        self.layout.addWidget(center_widget, True)  # True = add stretch vertically

        self.label = QtWidgets.QLabel()  # Putting it in initializePage would add another one each time the page is displayed when going back and forth
        self.layout.addWidget(self.label)

    def initializePage(self):
        print("Displaying ErrorPage")
        wizard.progress.hide()
        wizard.playSound()
        self.label.setWordWrap(True)
        self.label.clear()
        self.label.setText(wizard.error_message_nice)
        self.setButtonText(wizard.CancelButton, tr("Quit"))
        wizard.setButtonLayout([QtWidgets.QWizard.CustomButton1, QtWidgets.QWizard.Stretch, QtWidgets.QWizard.CancelButton])


#############################################################################
# Pages flow in the wizard
#############################################################################

# TODO: Go straight to error page if we are not able to run
# the installer shell script as root (e.g., using sudo).
# We do not want to run this GUI as root, only the installer shell script.

# TODO: Check prerequisites and inspect /mnt, go straight to error page if needed

# language_page = LanguagePage() # Currently broken at least on KDE
# wizard.addPage(language_page)
intro_page = IntroPage()
wizard.addPage(intro_page)
license_page = LicensePage()
wizard.addPage(license_page)
disk_page = DiskPage()
wizard.addPage(disk_page)
installation_page = InstallationPage()
wizard.addPage(installation_page)
success_page = SuccessPage()
wizard.addPage(success_page)

wizard.show()
sys.exit(app.exec_())
