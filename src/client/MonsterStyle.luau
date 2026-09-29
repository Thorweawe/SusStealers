--!strict
--[[
	Canavarların KOVALAMA karakteri (2026-09-29, "hepsi aynı kovalıyor,
	kovaladığı belli olmuyor, ses yok, heyecan gelmiyor").

	Her canavarın kendi yürüyüşü (gait) ve sesleri var:

	  Glorp        — balçık: zıplayarak, her inişte "şlap"
	  Chomper      — dörtnala, çenesi şak şak kapanıyor (her kapanışta ısırık)
	  Nebula Kraken— itişlerle yüzüyor: dokunaçlar toplanıp açılıyor, "vuuş"
	  Sand Maw     — kum solucanı: kıvrılarak, yaprak çeneleri açık, gürleme
	  Rift Stalker — örümcek: hızlı seğirme, çene kıskaçları tıkırdıyor
	  Void Leviathan — yılan: sağa sola süzülüyor, derin metalik uğultu

	Kovalama ağırlığı `k` (0 boşta .. 1 tam kovalama) yumuşak geçiş için:
	yürüyüş k ile karışıyor. Sesler 3B: canavarın kök parçasında, yakında
	yüksek. Kükreme sunucunun "roar" olayında (SpaceFX).

	Sesler Roblox'un kendi kütüphanesinden (SoundFX'teki kural); hepsinin
	yüklendiği Studio'da ölçüldü.
]]

local SoundService = game:GetService("SoundService")

local MonsterStyle = {}

export type Mods = {
	lift: number,   -- yukarı (stud, ölçeksiz)
	pitch: number,  -- öne eğilme (radyan, eksi = öne)
	roll: number,
	yaw: number,
	surge: number,  -- ileri atılma (stud, ölçeksiz)
	sway: number,   -- kemik salınımı çarpanı
	rate: number,   -- salınım hızı çarpanı
	roar: number,   -- çene/ağız açıklığı eklentisi
}

type Clip = { id: string, speed: number, volume: number, length: number }

type Style = {
	freq: number,            -- yürüyüş fazı hızı (radyan/sn)
	beats: number,           -- bir tam turda kaç adım sesi
	gait: (p: number, k: number) -> Mods,
	roar: Clip,
	step: Clip,
}

local function mods(lift: number, pitch: number, roll: number, yaw: number, surge: number, sway: number, rate: number, roar: number): Mods
	return { lift = lift, pitch = pitch, roll = roll, yaw = yaw, surge = surge, sway = sway, rate = rate, roar = roar }
end

local STYLES: { [string]: Style } = {
	Glorp = {
		freq = 5.2, beats = 2,
		gait = function(p, k)
			local hop = math.abs(math.sin(p))
			return mods(hop * 3.6 * k, (-0.1 + 0.12 * math.cos(2 * p)) * k, 0, 0, 0, 1.3, 1.6, 0.25 * k)
		end,
		roar = { id = "rbxassetid://9113095299", speed = 0.8, volume = 1.3, length = 0.9 },
		step = { id = "rbxassetid://9126210223", speed = 1.15, volume = 0.7, length = 0.6 },
	},
	Chomper = {
		freq = 9, beats = 1,
		gait = function(p, k)
			local jaw = 0.5 - 0.5 * math.cos(p)
			return mods(math.abs(math.sin(p)) * 1.4 * k, -0.22 * k, math.sin(p) * 0.07 * k, 0, 0, 1.8, 2.6, (0.15 + 0.75 * jaw) * k)
		end,
		roar = { id = "rbxassetid://9113972227", speed = 1.05, volume = 1.1, length = 2.4 },
		step = { id = "rbxassetid://9119055432", speed = 1, volume = 0.8, length = 0.5 },
	},
	Kraken = {
		freq = 3.4, beats = 1,
		gait = function(p, k)
			local pulse = 0.5 + 0.5 * math.sin(p)
			return mods(1.5 * pulse * k, -0.45 * k, 0, 0, 3 * pulse * k, 1 + 1.6 * (1 - pulse) * k, 2.2, 0.2 * k)
		end,
		roar = { id = "rbxassetid://9125889147", speed = 0.85, volume = 1.1, length = 2.5 },
		step = { id = "rbxassetid://9126234246", speed = 1.3, volume = 0.55, length = 0.9 },
	},
	SandMaw = {
		freq = 2.4, beats = 1,
		gait = function(p, k)
			return mods(0, (-0.25 + math.sin(p) * 0.05) * k, math.sin(p) * 0.14 * k, math.sin(p * 0.5) * 0.1 * k, 0, 2, 1.8, (0.7 + 0.25 * math.sin(p * 2)) * k)
		end,
		roar = { id = "rbxassetid://9120030737", speed = 0.8, volume = 1.1, length = 3 },
		step = { id = "rbxassetid://9125893684", speed = 1.2, volume = 0.55, length = 1.2 },
	},
	RiftStalker = {
		freq = 12, beats = 1,
		gait = function(p, k)
			return mods(math.abs(math.sin(p)) * 0.5 * k, -0.12 * k, math.sin(p) * 0.04 * k, 0, 0, 2.6, 4.2, (0.3 + 0.5 * math.abs(math.sin(p * 1.3))) * k)
		end,
		roar = { id = "rbxassetid://9113989720", speed = 0.9, volume = 1.2, length = 1.2 },
		step = { id = "rbxassetid://9126280361", speed = 1.6, volume = 0.5, length = 0.5 },
	},
	VoidLeviathan = {
		freq = 2, beats = 1,
		gait = function(p, k)
			return mods(math.sin(p) * 1.5 * k, -0.15 * k, math.sin(p + 1) * 0.1 * k, math.sin(p) * 0.18 * k, 0, 2.2, 1.7, (0.55 + 0.25 * math.sin(p * 2)) * k)
		end,
		roar = { id = "rbxassetid://9116292530", speed = 0.6, volume = 1.3, length = 3 },
		step = { id = "rbxassetid://9118750706", speed = 0.8, volume = 0.55, length = 2 },
	},
}

local IDLE: Mods = mods(0, 0, 0, 0, 0, 1, 1, 0)

local function group(): SoundGroup?
	local g = SoundService:FindFirstChild("Effects")
	return if g and g:IsA("SoundGroup") then g else nil
end

local function sound(parent: Instance, clip: Clip, scale: number): Sound
	local s = Instance.new("Sound")
	s.SoundId = clip.id
	s.Volume = clip.volume
	s.PlaybackSpeed = clip.speed
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 30 * scale
	s.RollOffMaxDistance = 420
	s.SoundGroup = group()
	s.Parent = parent
	return s
end

local function play(s: Sound, length: number)
	s:Stop()
	s.TimePosition = 0
	s:Play()
	task.delay(length, function()
		if s.IsPlaying then
			s:Stop()
		end
	end)
end

export type Voice = {
	phase: number,
	beat: number,
	roarSound: Sound?,
	stepSound: Sound?,
	style: Style?,
}

--[[ Canavar modeline sesleri takar. `root` modelin kök parçası (Pose onu taşıyor). ]]
function MonsterStyle.Attach(id: string, root: BasePart, scale: number): Voice
	local style = STYLES[id]
	local voice: Voice = { phase = math.random() * 6, beat = 0, style = style }
	if style then
		voice.roarSound = sound(root, style.roar, scale)
		voice.stepSound = sound(root, style.step, scale)
	end
	return voice
end

--[[ Kükreme (canavar uyandı). ]]
function MonsterStyle.Roar(voice: Voice)
	local style = voice.style
	if style and voice.roarSound then
		play(voice.roarSound, style.roar.length)
	end
end

--[[
	Bir kare: fazı ilerletir, kovalama ağırlığı k ile yürüyüşü verir.
	`audible` kamera yakınsa adım sesi çalar (uzaktaki canavarlar sessiz).
]]
function MonsterStyle.Step(voice: Voice, dt: number, k: number, audible: boolean): Mods
	local style = voice.style
	if not style or k < 0.01 then
		return IDLE
	end
	voice.phase += dt * style.freq * (0.4 + 0.6 * k)
	local beat = math.floor(voice.phase / (2 * math.pi) * style.beats)
	if beat ~= voice.beat then
		voice.beat = beat
		if audible and k > 0.5 and voice.stepSound then
			play(voice.stepSound, style.step.length)
		end
	end
	return style.gait(voice.phase, k)
end

return MonsterStyle
