--!strict
-- Oyunun sesleri. Tamamen istemci tarafı: fon uğultusu ve geri bildirim
-- sesleri sunucunun bilmesi gereken şeyler değil, ağ trafiği üretmiyorlar
-- ve her oyuncu kendi ses seviyesini duyuyor.
--
-- Ses kimlikleri burada tek yerde. Yeni ses eklemek için Creator Store'dan
-- alıp ID'sini buraya yazmak yeterli.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local SoundFX = {}

--[[
	Ses kimlikleri.

	Hepsi Roblox'un KENDİ ses kütüphanesinden (AssetService:SearchAudio ile
	bulundu) ve hepsinin bu yerde yüklendiği ölçülerek doğrulandı. Roblox
	bu kütüphaneyi creator'lar için lisanslıyor, yani oyun içinde kullanmak
	serbest.

	Müzik yerine DOKU seçildi — şarkı değil, dron ve uzay atmosferi. İki
	sebep: temaya (Among Us / istasyon) melodik prodüksiyon müziğinden daha
	çok oturuyor, ve biri oynanışı kaydedip dışarı koyduğunda telif
	taraması takılmıyor.

	HEPSİNİN BAŞLIĞINDA "Constant" VAR ve bu bilinçli: sürekli ses oldukları
	için neresinden kesilirse kesilsin geçerli bir tını çıkıyor. Derleme
	dosyalarından körlemesine kesit almak, sessizliğe ya da bir vuruşun
	ortasına denk gelme riski taşıyordu.
]]
local ID = {
	-- Fon: istasyon gövdesi ve makine
	Ambient = "rbxassetid://9113652844",   -- Buzzy Ambience Constant Gritty Drone 1
	Machine = "rbxassetid://91861694498690",
	Alarm   = "rbxassetid://9113392056",   -- Beeps Constant Fast Cluster Bursts Alarm 2

	-- Arayüz tonları: dördü de farklı TİMBRE, aynı aileden
	UiA     = "rbxassetid://9113120937",   -- Analysis Tone Ui Scan 1
	UiB     = "rbxassetid://9113120926",   -- Analysis Tone Ui Scan 2
	UiC     = "rbxassetid://9113120949",   -- Analysis Tone Ui Scan 3
	UiD     = "rbxassetid://9113121236",   -- Analysis Tone Ui Scan 4

	-- Ağır / mekanik işler
	Throb   = "rbxassetid://9119838397",   -- Synth Throb Constant Low Frequency 1

	-- Asteroit oyunu (Weapons): atış ve kaya kırılması. Among Us'ın kendi
	-- sesleri telifli; bunlar Roblox kütüphanesinden benzer tınılar.
	Laser   = "rbxassetid://9116225257",   -- Laser Blast 101 (Pro Sound Effects)
	Rock    = "rbxassetid://9118588165",   -- Rock Drop On Concrete Breaks 10

	-- Oda görevleri (TaskGames): kablo tutma / bağlama, kart kaydırma / onay
	WireGrab   = "rbxassetid://9120489791",   -- Wall Switch Click 12
	WireZap    = "rbxassetid://9114277402",   -- Electric Zaps 6
	CardSwipe  = "rbxassetid://9113722807",   -- Card Swipe 8
	CardAccept = "rbxassetid://9119764754",   -- Synth Beeps High Pitch 6

	-- Ekipman (GearFX): savurma, tokat, şok, patlama, hayalet serumu
	GearSwing = "rbxassetid://9120718279",   -- Whoosh Fast Swish By 1
	GearSlap  = "rbxassetid://9113512874",   -- Body Hit Slaps 10
	GearZap   = "rbxassetid://9114277338",   -- Electric Zaps 4
	GearBlast = "rbxassetid://9114362774",   -- Explosions 5
	GearPoof  = "rbxassetid://9116406375",   -- Magic Poofs Thumpy Wheezy Exhale 1

	-- Eski red sesi korunuyor: kısa ve boğuk, hata için doğru
	Deny    = "rbxassetid://87437544236708",
	Success = "rbxassetid://125296945528316",
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

-- Fon sürekli çaldığı için efektlerden belirgin kısık; kullanıcı
-- "baş ağrıtıyor" dediği için ikisi de düşürüldü.
local AMBIENCE_VOLUME = 0.18
local EFFECT_VOLUME = 0.45
local ambienceGroup = ensureGroup("Ambience", AMBIENCE_VOLUME)
local effectGroup = ensureGroup("Effects", EFFECT_VOLUME)

--[[
	Oyuncunun efekt sesi ayarı (SettingsService -> "SettingSfx" niteliği,
	0..1). Taban seviyeyle çarpılıyor; fon da efekt sayılıyor.
]]
do
	local player = game:GetService("Players").LocalPlayer
	local function applySetting()
		local v = player:GetAttribute("SettingSfx")
		local k = if typeof(v) == "number" then math.clamp(v, 0, 1) else 1
		ambienceGroup.Volume = AMBIENCE_VOLUME * k
		effectGroup.Volume = EFFECT_VOLUME * k
	end
	player:GetAttributeChangedSignal("SettingSfx"):Connect(applySetting)
	applySetting()
end

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
local AMBIENT_ENABLED = false

function SoundFX.StartAmbient()
	--[[
		KAPALI. Sürekli çalan gıcırtılı dron ("Gritty Drone") müziğin altında
		durmadan vızıldıyordu ve oyuncu "baş ağrıtıyor" dedi. Atmosferi
		artık gerçek müzik (Music.luau) veriyor; fon sesine gerek kalmadı.
		Geri açmak için AMBIENT_ENABLED'ı true yap.
	]]
	if ambient or not AMBIENT_ENABLED then
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

	--[[
		Uğultu dengesi.

		Önce 0.35 sesle ve 8 stud tam-ses yarıçapıyla çalıyordu. Oyuncu
		konveyörün BAŞINDA duruyor (orada satın alıyor), yani 1.93 saniyelik
		kısa bir döngü sürekli tam sesle tepesinde dönüyordu — baş ağrıtıyor.

		Üç değişiklik: ses yarıya indi, tam-ses yarıçapı 8'den 3'e indi
		(yani yanında bile hafif), duyulma mesafesi 70'ten 42'ye indi
		(komşu üslerin uğultusu üst üste binmesin).
	]]
	-- İkinci kısma: 1.93 sn'lik kısa döngü yine de tekrarı duyuruyordu
	local s = newSound(ID.Machine, anchor, ambienceGroup, 0.08, true)
	s.Name = "MachineHum"
	s.RollOffMaxDistance = 30
	s.RollOffMinDistance = 3
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
	Asteroit atışı: kaydın yalnızca başındaki kısa "pew". Tamamı 3 sn ve
	art arda atışta üst üste binince gürültüye dönüşüyordu.
]]
function SoundFX.Laser()
	fire("Laser", 0, 0.35)
end

function SoundFX.RockBreak()
	fire("Rock", 0, 0.6)
end

--[[
	Oda görevlerinin sesleri (TaskGames). Kayıtların başından kısa kesitler:
	kıvılcım ve bip uzun kayıtlar, tamamı çalınca görevin temposunu boğuyordu.
]]
local TASK_SOUNDS: { [string]: { key: string, length: number } } = {
	wireGrab = { key = "WireGrab", length = 0.3 },
	wireConnect = { key = "WireZap", length = 0.45 },
	cardSwipe = { key = "CardSwipe", length = 0.8 },
	cardAccept = { key = "CardAccept", length = 0.5 },
}

function SoundFX.TaskSound(kind: string)
	local def = TASK_SOUNDS[kind]
	if def then
		fire(def.key, 0, def.length)
	end
end

-- ─── Olay sesleri ───────────────────────────────────────────────────────────

--[[
	Her işlem kendi sesini çalıyor.

	Önce bütün başarılı işlemler tek bir "Success" tınısıydı: satın alma,
	satma, yükseltme, görev, unvan hepsi aynı geliyordu ve hangi işlemin
	tuttuğu kulaktan anlaşılmıyordu. Sunucu artık bildirimin TÜRÜNÜ de
	gönderiyor (Notify'ın dördüncü argümanı), burada ona bakıyoruz.

	AYRI ÖRNEK YOK, DİYE BEKLEMİYORUZ. Her tür için ayrı ses dosyası
	yüklenene kadar tınıyı aynı örnekten TÜRETİYORUZ: perde (pitch),
	ses seviyesi ve tekrar sayısı. Bu üçü bir arada gerçekten ayırt
	edilebilir işaretler veriyor —

	  alçak + tek vuruş   → ağır, kalıcı şeyler (kat, rebirth)
	  yüksek + tek vuruş  → hafif, sık şeyler (satın alma, satma)
	  çoklu vuruş         → kutlama (rozet, unvan, görev)

	Gerçek örnekler geldiğinde tek yapılacak şey `id` alanını doldurmak;
	çağıran taraf hiç değişmiyor.

	concept: Among Us / uzay istasyonu. Sesler kısa, kuru ve elektronik
	olmalı; orkestral ya da fantastik tınılar temayı bozuyor.
]]
--[[
	Tınılar Config'te (Config.NotifyCues).

	Orada çünkü hangi türlerin var olduğu SUNUCU ile İSTEMCİNİN ortak
	bilgisi: sunucu türü gönderiyor, istemci sesi seçiyor. Ayrı yerlerde
	dursaydı sunucuya yeni bir tür eklenip buraya yazılmadığında o işlem
	sessizce taban sese düşer ve kimse fark etmezdi. Bir test iki tarafın
	ayrışmasını yakalıyor.
]]

--[[
	Tek seferlik ses örneği.

	Paylaşılan örneğin perdesini değiştirip bırakırsak bir sonraki çalan
	ses de o perdeden çalar. Çoklu vuruşta üst üste binmeleri de gerekiyor.
	O yüzden burada her vuruş için ayrı, çalınca kendini silen bir Sound
	yaratıyoruz — kısa arayüz sesleri için bu maliyet önemsiz.
]]
local function playOnce(cue: Config.NotifyCue, pitch: number)
	--[[
		Kaynak örnek. Uzun örneklerden (Machine / Alarm / Ambient) bir kesit
		almak tımbre farkının asıl kaynağı: mekanik bir "güm" ile parlak bir
		"ping" aynı perdede bile karıştırılmıyor.
	]]
	local id = ID[cue.source or "Success"] or ID.Success

	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = cue.volume
	s.PlaybackSpeed = pitch
	s.SoundGroup = effectGroup
	s.Parent = SoundService
	s:Play()

	if cue.startAt then
		-- TimePosition yalnızca çalarken uygulanabiliyor
		s.TimePosition = cue.startAt
	end

	--[[
		Kesit süresi. Perde değiştiğinde ses de hızlanıyor, o yüzden gerçek
		süre perdeye bölünüyor — yoksa alçak perdede kesit uzuyor ve
		kutlama sesleri birbirine giriyordu.
	]]
	local window = cue.length
	if window then
		task.delay(window / math.max(0.1, pitch), function()
			if s.IsPlaying then
				s:Stop()
			end
			s:Destroy()
		end)
	else
		s.Ended:Once(function()
			s:Destroy()
		end)
	end

	-- Ended bazı durumlarda hiç gelmiyor (ses yüklenemezse); sızıntı olmasın
	game:GetService("Debris"):AddItem(s, 6)
end

--[[
	Bildirim türüne göre ses çalar.

	Tanınmayan tür sessizce taban sese düşüyor: sunucuya yeni bir tür
	eklenip burası unutulursa oyuncu ses duymamazlık etmesin.
]]
function SoundFX.Event(kind: string?, isError: boolean)
	if isError then
		SoundFX.Deny()
		return
	end

	local cue = if kind then Config.NotifyCues[kind] else nil
	if not cue then
		SoundFX.Success()
		return
	end

	local repeats = cue.repeats or 1

	if repeats <= 1 then
		playOnce(cue, cue.pitch)
		return
	end

	--[[
		Çoklu vuruşta perde her vuruşta biraz yükseliyor: düz tekrar
		"takıldı" gibi duruyor, yükselen dizi "tamamlandı" diyor.
	]]
	task.spawn(function()
		for i = 1, repeats do
			playOnce(cue, cue.pitch * (1 + (i - 1) * 0.09))
			if i < repeats then
				task.wait(cue.gap or 0.1)
			end
		end
	end)
end

--[[ Bir türün tanımlı olup olmadığı. Testler ve tanı için. ]]
function SoundFX.HasCue(kind: string): boolean
	return Config.NotifyCues[kind] ~= nil
end

--[[
	Alarm kaydı 33 saniye. Çalınma anında tepki anlık olmalı; vurucu kısımdan
	başlatıp kısa sürede kesiyoruz, 33 saniye alarm dinletmek işkence olur.
]]
function SoundFX.Alarm()
	fire("Alarm", 0.15, 2.2)
end

--[[
	Takip alarmı: hırsız karakteri kendi üssüne bırakana kadar çalmaya devam
	eder. Tek seferlik bip "bir şey oldu" diyor; süren alarm "hâlâ oluyor,
	yetişebilirsin" diyor. Kovalamacanın gerilimi buradan geliyor.

	shouldContinue her turda soruluyor — hırsız bıraktığı, öldüğü ya da
	oyundan çıktığı anda susuyor. maxSeconds güvenlik sınırı: bir şey ters
	giderse alarm sonsuza kadar çalmasın.
]]
local pursuitToken = 0

function SoundFX.AlarmUntil(shouldContinue: () -> boolean, maxSeconds: number)
	pursuitToken += 1
	local token = pursuitToken

	task.spawn(function()
		local s = effects["Alarm"]
		if not s then
			return
		end

		--[[
			Kesik bip ritmi. Kaydı 2 saniyede bir baştan çalmak denendi ama
			vurucu kısım o kadar sürmediği için bindirme oluyor ve döngü
			dikişi duyuluyordu. Kısa bir dilim çalıp susmak hem temiz hem de
			gerçek bir alarma daha çok benziyor.
		]]
		--[[
			Bip daha kısa, ara daha uzun. Önceki ritim (0.85 çal / 0.75 sustur)
			45 saniye boyunca neredeyse kesintisiz siren demekti ve baş
			ağrıtıyordu. Şimdi kısa bir uyarı, sonra nefes.
		]]
		local BEEP = 0.45
		local GAP = 1.60

		local deadline = os.clock() + maxSeconds
		while os.clock() < deadline do
			if token ~= pursuitToken then
				return -- yeni bir takip başladı
			end
			if not shouldContinue() then
				break
			end

			s:Stop()
			s.TimePosition = 0.2
			s:Play()
			task.wait(BEEP)

			if token ~= pursuitToken then
				return
			end
			s:Stop()
			task.wait(GAP)
		end

		if token == pursuitToken and s.IsPlaying then
			s:Stop()
		end
	end)
end

--[[ Takibi erken bitirir (karakteri geri aldığında). ]]
function SoundFX.StopAlarm()
	pursuitToken += 1
	local s = effects["Alarm"]
	if s and s.IsPlaying then
		s:Stop()
	end
end

--[[
	Ekipman sesleri DÜNYADA çalıyor: başka oyuncunun tokadı uzaktan kısık
	duyuluyor. Şablonlar Preload'da bir kez yükleniyor, her çalışta
	kopyası o noktaya konup bitince siliniyor (yüklü kopya anında çalıyor).
]]
local GEAR_SOUNDS: { [string]: { volume: number, length: number } } = {
	GearSwing = { volume = 0.5, length = 0.5 },
	GearSlap = { volume = 0.9, length = 0.8 },
	GearZap = { volume = 0.6, length = 0.9 },
	GearBlast = { volume = 0.7, length = 1.6 },
	GearPoof = { volume = 0.7, length = 1.0 },
}

function SoundFX.GearSound(key: string, position: Vector3)
	local spec = GEAR_SOUNDS[key]
	if not spec then
		return
	end
	local template = effect(key, ID[key], spec.volume)
	local holder = Instance.new("Attachment")
	holder.Name = "GearSound"
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local s = template:Clone()
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 140
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.Parent = holder
	s:Play()
	task.delay(spec.length, function()
		holder:Destroy()
	end)
end

--[[
	Sesleri önden yükler. Oyuna girer girmez çağrılmalı: ilk tetiklemeden
	önce hazır olsunlar diye.
]]
function SoundFX.Preload()
	effect("Success", ID.Success, 0.75)
	effect("Deny", ID.Deny, 0.55)
	effect("Alarm", ID.Alarm, 0.55)
	effect("Laser", ID.Laser, 0.35)
	effect("Rock", ID.Rock, 0.45)
	effect("WireGrab", ID.WireGrab, 0.5)
	effect("WireZap", ID.WireZap, 0.4)
	effect("CardSwipe", ID.CardSwipe, 0.6)
	effect("CardAccept", ID.CardAccept, 0.4)
	for key, spec in GEAR_SOUNDS do
		effect(key, ID[key], spec.volume)
	end

	-- Olay tınılarının kaynakları da önden yüklensin: ilk tetiklemede
	-- sessizlik olmasın
	for _, key in { "UiA", "UiB", "UiC", "UiD", "Throb" } do
		effect(key, ID[key], 0.5)
	end

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
