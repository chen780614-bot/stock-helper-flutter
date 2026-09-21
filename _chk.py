from pathlib import Path
import re
t=Path(r'C:\Users\user\Documents\stock-helper-flutter\lib\services\holdings_ocr.dart').read_text(encoding='utf-8')
m=re.search(r"const _typeNoise = \{(.*?)\};", t, re.S)
block=m.group(1)
def dart_unescape(s):
    return re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1),16)), s)
print(dart_unescape(block))
print('--- error ---')
m2=re.search(r"StateError\('([^']+)'\)", t)
print(dart_unescape(m2.group(1)))