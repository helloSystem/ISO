# /usr/local/bin/env python3


# Translate Python applications using Qt .ts files without the need for compilation


# Copyright (c) 2021, Simon Peter <probono@puredarwin.org>
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


import os, locale

try:
    from translate.storage.ts2 import tsfile # sudo python3 -m pip install translate-toolkit
except:
    print("The Python module 'translate' is not available. The application will run untranslated.")

class TsTranslator(object):

    def __init__(self, translations_dir, translations_file_prefix):
        self.ts = None
        long_locale = locale.getlocale()[0]  # de_DE
        short_locale = long_locale.split("_")[0]  # de
        candidates = [long_locale, short_locale, "en", "en_US"]
        for candidate in candidates:
            p = translations_dir + "/" + candidate + ".ts"
            if translations_file_prefix:
                p = translations_dir + "/" + translations_file_prefix + "_" + candidate + ".ts"
            if os.path.exists(p):
                # print(p)
                try:
                    self.ts = tsfile.parsefile(p)
                    print("Loaded translations from %s" % p)
                    break
                except:
                    print("Translations could not be loaded.")
                    break
        if not self.ts:
            print("Could not find suitable .ts files in %s" % translations_dir)

    def tr(self, input):
        if not self.ts:
            return(input)
        unit = self.ts.findunit(input)
        if not unit:
            return(input)
        output = unit.target
        if not output:
            return(input)
        return(output)


if __name__ == "__main__":
    tstr = TsTranslator(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))) + "/i18n", None)
    print(tstr.tr("Hello World"))
