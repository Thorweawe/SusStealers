"""
Studio'ya dosya basmak için run_code betiği üretir (sync köprüsü ve HttpService
kapalıyken, DEVIR 85-86). Studio'daki sürüm `base` commit'iyse yalnızca
değişen parçaları gönderir (bul/değiştir), sonra hash'i kontrol edip ancak
tutarsa yazar. Yeni dosyada tam kaynak + ModuleScript oluşturma.

Yazma ScriptEditorService:UpdateSourceAsync ile: .Source ataması 200 000
karakterde kesiliyor (Config bunu aşıyor) ve Team Create taslaklarıyla uyumlu.

    python tools/studio_patch.py <base commit|NEW> <hedef commit> <dosya> > out.lua

Hash: \\r atılmış baytlarda len|h, h = (h*31 + b) % 1000000007.
"""
import difflib
import glob
import subprocess
import sys

GIT = sorted(glob.glob(r"C:/Users/yasuo/AppData/Local/GitHubDesktop/app-*/resources/app/git/cmd/git.exe"))[-1]
NL = "\n"


def show(rev: str, path: str) -> str:
    return subprocess.check_output([GIT, "show", f"{rev}:{path}"]).decode("utf-8").replace("\r", "")


def h(s: str) -> str:
    x = 0
    b = s.encode("utf-8")
    for c in b:
        x = (x * 31 + c) % 1000000007
    return f"{len(b)}|{x}"


def lstr(s: str) -> str:
    n = 1
    while ("]" + "=" * n + "]") in s or s.endswith("]" + "=" * (n - 1)):
        n += 1
    return "[" + "=" * n + "[" + NL + s + "]" + "=" * n + "]"


def target_path(path: str) -> tuple[str, str]:
    name = path.split("/")[-1].replace(".luau", "")
    if path.startswith("src/shared/"):
        return "game.ReplicatedStorage.Shared", name
    if path.startswith("src/server/"):
        return "game.ServerScriptService.Server", name
    if path == "src/client/init.client.luau":
        return "game.StarterPlayer.StarterPlayerScripts", "Client"
    return "game.StarterPlayer.StarterPlayerScripts.Client", name


WRITE = ("local f_, e_ = loadstring(src) if not f_ then print('DERLEME HATASI', e_) return end" + NL
         + "game:GetService('ScriptEditorService'):UpdateSourceAsync(s, function() return src end)" + NL
         + "print('yazildi', s:GetFullName(), H(s.Source))" + NL)


def ops_for(base: str, new: str) -> list[tuple[str, str]]:
    a, b = base.split(NL), new.split(NL)
    codes = difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes()

    def amap(p: int) -> int:
        for tag, i1, i2, j1, j2 in codes:
            if tag == "equal" and i1 <= p <= i2:
                return j1 + (p - i1)
        for tag, i1, i2, j1, j2 in codes:
            if p == i1:
                return j1
            if p == i2:
                return j2
        raise ValueError(p)

    ranges = [[max(0, i1 - 2), min(len(a), i2 + 2)] for tag, i1, i2, _, _ in codes if tag != "equal"]
    # base içinde tek olana kadar genişlet, sonra çakışan/bitişikleri birleştir
    for r in ranges:
        while base.count(NL.join(a[r[0]:r[1]])) > 1 and (r[0] > 0 or r[1] < len(a)):
            r[0], r[1] = max(0, r[0] - 2), min(len(a), r[1] + 2)
    ranges.sort()
    merged: list[list[int]] = []
    for r in ranges:
        if merged and r[0] <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], r[1])
        else:
            merged.append(list(r))
    return [(NL.join(a[lo:hi]), NL.join(b[amap(lo):amap(hi)])) for lo, hi in merged]


def main():
    base_rev, new_rev, path = sys.argv[1], sys.argv[2], sys.argv[3]
    new = show(new_rev, path)
    parent, name = target_path(path)
    out = [f"local parent = {parent}", f"local s = parent:FindFirstChild({name!r})",
           "local function H(t) t = t:gsub('\\r', '') local x = 0 for i = 1, #t do x = (x * 31 + string.byte(t, i)) "
           "% 1000000007 end return #t .. '|' .. x end"]
    if base_rev == "NEW":
        out += [f"local src = {lstr(new)}",
                f"if not s then s = Instance.new('ModuleScript') s.Name = {name!r} s.Parent = parent end",
                f"if H(src) ~= {h(new)!r} then print('HASH UYMADI (gonderim)') return end"]
        print(NL.join(out) + NL + WRITE)
        return
    base = show(base_rev, path)
    out += ["if not s then print('YOK') return end",
            "local src = s.Source:gsub('\\r', '')",
            f"if H(src) ~= {h(base)!r} then print('TABAN FARKLI', H(src)) return end",
            "local function rep(old, new)",
            "\tlocal i, j = string.find(src, old, 1, true)",
            "\tif not i then error('parca yok: ' .. old:sub(1, 60)) end",
            "\tsrc = src:sub(1, i - 1) .. new .. src:sub(j + 1)",
            "end"]
    # Sondan başa: önceki parçalar henüz değişmemişken bulunuyor
    for old, newblk in reversed(ops_for(base, new)):
        out.append(f"rep({lstr(old)}, {lstr(newblk)})")
    out.append(f"if H(src) ~= {h(new)!r} then print('SONUC HASH UYMADI', H(src)) return end")
    print(NL.join(out) + NL + WRITE)


if __name__ == "__main__":
    main()
