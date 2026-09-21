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
	Tek seferlik ses. Her çağrıda yeni bir örnek yaratılıyor ki üst üste
	binebilsinler: art arda iki satış yapınca ikincisi birincisini kesmesin.
]]
local function playOnce(id: string, volume: number, startAt: number?)
	local s = newSound(id, SoundService, effectGroup, volume, false)
	if startAt then
		s.TimePosition = startAt
	end
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	-- Ended gelmezse (ses yüklenemezse) sızıntı olmasın
	task.delay(12, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function SoundFX.Success()
	playOnce(ID.Success, 0.7)
end

function SoundFX.Deny()
	playOnce(ID.Deny, 0.5)
end

--[[
	Alarm kaydı 33 saniye ve başı sessiz sayılabilecek kadar yumuşak.
	Vurucu kısımdan başlatıp kısa süre sonra kesiyoruz: çalınma anında
	tepki anlık olmalı, 33 saniye alarm dinletmek işkence olur.
]]
function SoundFX.Alarm()
	local s = newSound(ID.Alarm, SoundService, effectGroup, 0.75, false)
	s.TimePosition = 0.15
	s:Play()
	task.delay(2.2, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

return SoundFX
