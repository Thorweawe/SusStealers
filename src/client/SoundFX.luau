--!strict
-- Oyunun sesleri. Tamamen istemci tarafı: fon uğultusu ve geri bildirim
-- sesleri sunucunun bilmesi gereken şeyler değil, ağ trafiği üretmiyorlar
-- ve her oyuncu kendi ses seviyesini duyuyor.
--
-- Ses kimlikleri burada tek yerde. Yeni ses eklemek için Creator Store'dan
-- alıp ID'sini buraya yazmak yeterli.

local SoundService = game:GetService("SoundService")

local SoundFX = {}

local ID = {
	Ambient = "rbxassetid://9114330975",    -- istasyon fonu, uzun süzülme
	Machine = "rbxassetid://91861694498690", -- makine uğultusu, kısa döngü
	Alarm = "rbxassetid://7084812679",       -- acil durum alarmı
	Deny = "rbxassetid://87437544236708",    -- reddedildi
	Success = "rbxassetid://125296945528316", -- başarılı işlem
}

--[[
	Ses grubu: oyuncunun tek yerden kısabilmesi ve fon ile efektlerin
	birbirini bastırmaması için. Fon sürekli çaldığı için efektlerden
	belirgin şekilde kısık tutuluyor.
]]
local function ensureGroup(name: string, volume: number): SoundGroup
	local existing = SoundService:FindFirstChild(name)
	if existing and existing:IsA("SoundGroup") then
		existing.Volume = volume
		return existing
	end

	local groupObj = Instance.new("SoundGroup")
	groupObj.Name = name
	groupObj.Volume = volume
	groupObj.Parent = SoundService
	return groupObj
end

local ambienceGroup = ensureGroup("Ambience", 0.35)
local effectGroup = ensureGroup("Effects", 0.8)

local function newSound(id: string, parent: Instance, groupObj: SoundGroup, volume: number, looped: boolean): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Looped = looped
	s.SoundGroup = groupObj
	s.Parent = parent
	return s
end

-- ─── Fon ────────────────────────────────────────────────────────────────────

local ambient: Sound? = nil

function SoundFX.StartAmbient()
	if ambient then
		return
	end
	ambient = newSound(ID.Ambient, SoundService, ambienceGroup, 0.5, true)
	;(ambient :: Sound):Play()
end

--[[
	Konveyör dağıtıcılarına konumlu uğultu. 3B ses olduğu için oyuncu
	yaklaştıkça yükseliyor; istasyonun çalıştığı hissini veriyor.
	Kaynak ses kısa, döngüye alınıyor.
]]
function SoundFX.AttachMachineHum(anchor: BasePart)
	if anchor:FindFirstChild("MachineHum") then
		return
	end

	local s = newSound(ID.Machine, anchor, ambienceGroup, 0.35, true)
	s.Name = "MachineHum"
	s.RollOffMaxDistance = 70
	s.RollOffMinDistance = 8
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s:Play()
end

-- ─── Efektler ───────────────────────────────────────────────────────────────

--[[
	Efekt sesleri kalıcı örnekler olarak bir kez yaratılıyor ve tekrar tekrar
	çalınıyor.

	Önceki hali her çağrıda yeni bir Sound yaratıp hemen Play() diyordu. Ses
	dosyası henüz akışla gelmediyse o çağrı sessizce kayboluyordu — ilk
	satın alma, ilk çalma hiç ses çıkarmıyordu. Kalıcı örnek bir kez yüklenip
	hazır bekliyor, sonraki çalmalar anında.

	Bedeli: art arda çok hızlı iki tetikleme olursa ikincisi birincisini
	baştan başlatıyor. Kısa arayüz seslerinde bu fark edilmiyor.
]]
local effects: { [string]: Sound } = {}

local function effect(key: string, id: string, volume: number): Sound
	local existing = effects[key]
	if existing then
		return existing
	end

	local s = newSound(id, SoundService, effectGroup, volume, false)
	s.Name = key
	effects[key] = s
	return s
end

local function fire(key: string, startAt: number?, stopAfter: number?)
	local s = effects[key]
	if not s then
		return
	end

	s:Stop()
	s.TimePosition = startAt or 0
	s:Play()

	if stopAfter then
		task.delay(stopAfter, function()
			if s.IsPlaying then
				s:Stop()
			end
		end)
	end
end

function SoundFX.Success()
	fire("Success")
end

function SoundFX.Deny()
	fire("Deny")
end

--[[
	Alarm kaydı 33 saniye. Çalınma anında tepki anlık olmalı; vurucu kısımdan
	başlatıp kısa sürede kesiyoruz, 33 saniye alarm dinletmek işkence olur.
]]
function SoundFX.Alarm()
	fire("Alarm", 0.15, 2.2)
end

--[[
	Sesleri önden yükler. Oyuna girer girmez çağrılmalı: ilk tetiklemeden
	önce hazır olsunlar diye.
]]
function SoundFX.Preload()
	effect("Success", ID.Success, 0.75)
	effect("Deny", ID.Deny, 0.55)
	effect("Alarm", ID.Alarm, 0.8)

	task.spawn(function()
		local ContentProvider = game:GetService("ContentProvider")
		local list = {}
		for _, s in effects do
			table.insert(list, s)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

return SoundFX
