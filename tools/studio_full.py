"""Studio'ya bir dosyanın TAM kaynağını basan run_code betiği (taban hash kontrolüyle).
    python tools/studio_full.py <taban commit> <dosya> > out.lua
Uzun kaynak [=====[ ... ]=====] içinde; derleme (loadstring) kontrolünden geçmezse yazmıyor."""
import subprocess, sys, glob
sys.path.insert(0, __import__('os').path.dirname(__file__))
from studio_patch import show, h, target_path as studio_path  # noqa
base, path = sys.argv[1], sys.argv[2]
old = show(base, path)
new = open(path, encoding='utf-8').read().replace('\r', '')
parent, name = studio_path(path)
eq = '=' * 6
print(f"""local parent = {parent}
local s = parent:FindFirstChild('{name}')
local function H(t) t = t:gsub(string.char(13), '') local x = 0 for i = 1, #t do x = (x * 31 + string.byte(t, i)) % 1000000007 end return #t .. '|' .. x end
if not s then print('YOK') return end
if H(s.Source) ~= '{h(old)}' then print('TABAN FARKLI', H(s.Source)) return end
local src = [{eq}[
{new}]{eq}]
if H(src) ~= '{h(new)}' then print('SONUC HASH UYMADI', H(src)) return end
local f, err = loadstring(src)
if not f then print('DERLEME HATASI', err) return end
game:GetService('ScriptEditorService'):UpdateSourceAsync(s, function() return src end)
print('yazildi', s:GetFullName(), H(s.Source))""")
