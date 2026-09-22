--!strict
--[[
	Müzik: bölgeye göre değişen fon parçaları.

	Neden ayrı bir modül: SoundFX kısa geri bildirim sesleri ve ortam
	uğultusu için. Müzik farklı davranıyor — uzun, döngülü, birbirine
	yumuşak geçiyor ve oyuncunun nerede olduğuna göre değişiyor.

	İKİ BÖLGE:
	  lobby   — sakin, geniş; oyuncu burada alışveriş yapıyor, acelesi yok
	  station — tempolu ama boğucu değil; asıl oyun burada geçiyor

	KISILMA (ducking): çalınma alarmı çalarken müzik geri çekiliyor.
	Alarm oyuncunun duyması GEREKEN şey; müzik onunla yarışmamalı.

	SES KİMLİĞİ YOKSA SESSİZ KALIYOR, HATA VERMİYOR. Liste boş olduğunda
	modül kurulup hiçbir şey çalmıyor — oyun çalışmaya devam ediyor.
	Kimlikler geldiğinde tek yapılacak şey aşağıdaki listeleri doldurmak.

	Parçalar Roblox'un kendi kütüphanesinden (AssetService:SearchAudio) ve
	bu yerde yüklendikleri ölçülerek doğrulandı.

	ŞARKI DEĞİL DOKU seçildi: dron ve gemi uğultusu. Temaya melodik
	prodüksiyon müziğinden daha çok oturuyor, ve biri oynanışı kaydedip
	dışarı koyduğunda telif taraması takılmıyor.

	Kimlik eklerken: Roblox'ta başkasının YÜKLEDİĞİ ses başka oyunda
	kullanılamıyor — katalogdan alınan kimlikler sessiz kalıyor. Studio'nun
	kendi ses kütüphanesini kullan ve eklemeden önce yüklendiğini doğrula.

	Kullanım (init.client.luau içinde):
		mountPanel("Music", function() Music.Start() end)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Music = {}

local player = Players.LocalPlayer

--[[
	Bölge başına çalma listesi.

	Birden fazla parça varsa sırayla ve karışık çalıyor; tek parça varsa
	döngüye giriyor. Boş liste = o bölgede müzik yok.

	Temaya uygun olması gereken şey: Among Us / uzay istasyonu. Sakin
	elektronik, hafif gerilim, orkestral olmayan. Tempolu bir parça
	istasyonda iyi durur; lobide daha yumuşak bir şey.
]]
local PLAYLIST: { [string]: { string } } = {
	-- Lobi: sakin, yakın; alışveriş yapılan yer
	lobby = {
		"rbxassetid://9113652844",   -- Buzzy Ambience Constant Gritty Drone 1
	},
	-- İstasyon: geniş ve alçak gemi uğultusu; asıl oyun burada
	station = {
		"rbxassetid://9125970753",   -- Spacecraft Engine Constant Mild Roar Rumble
	},
}

-- Müzik kendi grubunda: oyuncu ayarlardan efektlerden bağımsız kısabilsin
-- ve kısılma (ducking) tek yerden uygulanabilsin.
-- Doku müziği; öne çıkmamalı, altta durmalı
local BASE_VOLUME = 0.16
local DUCK_VOLUME = 0.03
local FADE = 1.5

local function ensureGroup(): SoundGroup
	local existing = SoundService:FindFirstChild("Music")
	if existing and existing:IsA("SoundGroup") then
		return existing
	end

	local group = Instance.new("SoundGroup")
	group.Name = "Music"
	group.Volume = BASE_VOLUME
	group.Parent = SoundService
	return group
end

export type Handle = {
	SetDucked: (ducked: boolean) -> (),
	Stop: () -> (),
}

--[[
	Oyuncunun hangi bölgede olduğu.

	Lobinin zeminini ADIYLA bulup sınırlarına bakıyoruz, koordinat
	yazmıyoruz: lobi taşınırsa ya da büyürse burası kendiliğinden uyuyor.
	Zemin bulunamazsa istasyon varsayılıyor — oyunun çoğu orada geçiyor.
]]
local function zoneOf(position: Vector3): string
	local decor = workspace:FindFirstChild("Decor")
	local lobby = decor and decor:FindFirstChild("Lobby")
	local deck = lobby and lobby:FindFirstChild("LobbyDeck")

	if not (deck and deck:IsA("BasePart")) then
		return "station"
	end

	local delta = position - deck.Position
	local inside = math.abs(delta.X) <= deck.Size.X / 2
		and math.abs(delta.Z) <= deck.Size.Z / 2

	return if inside then "lobby" else "station"
end

function Music.Start(): Handle
	local group = ensureGroup()

	local current: Sound? = nil
	local currentZone = ""
	local ducked = false
	local playToken = 0
	local stopped = false

	local function targetVolume(): number
		return if ducked then DUCK_VOLUME else BASE_VOLUME
	end

	local function fadeGroup(to: number)
		TweenService:Create(
			group,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Volume = to }
		):Play()
	end

	--[[
		Çalan parçayı söndürüp siliyor. Anında kesmek sert duruyor;
		yumuşak geçiş iki parçanın bir an üst üste binmesini gerektiriyor,
		o yüzden eski parça yeni parça başladıktan sonra sönüyor.
	]]
	local function fadeOut(sound: Sound)
		local tween = TweenService:Create(
			sound,
			TweenInfo.new(FADE, Enum.EasingStyle.Linear),
			{ Volume = 0 }
		)
		tween:Play()
		tween.Completed:Once(function()
			sound:Destroy()
		end)
	end

	--[[
		Bölgenin listesinden sırayla çalıyor, sonuna gelince başa dönüyor.

		Parça bittiğinde bir sonrakine geçmek için Ended'ı dinliyoruz;
		zamanlayıcı kurmuyoruz çünkü parça uzunluğu yüklenmeden bilinmiyor.
	]]
	local function playZone(zone: string)
		local list = PLAYLIST[zone]
		if not list or #list == 0 then
			-- O bölgede müzik yok: çalanı sustur, yenisini başlatma
			if current then
				fadeOut(current)
				current = nil
			end
			currentZone = zone
			return
		end

		playToken += 1
		local token = playToken
		currentZone = zone

		local order = table.clone(list)
		-- Karıştır: her oturumda aynı sırayla başlamasın
		for i = #order, 2, -1 do
			local j = math.random(i)
			order[i], order[j] = order[j], order[i]
		end

		task.spawn(function()
			local index = 0

			while not stopped and playToken == token do
				index += 1
				if index > #order then
					index = 1
				end

				local sound = Instance.new("Sound")
				sound.SoundId = order[index]
				sound.Volume = 0
				sound.Looped = #order == 1
				sound.SoundGroup = group
				sound.Parent = SoundService

				local previous = current
				current = sound
				sound:Play()

				TweenService:Create(
					sound,
					TweenInfo.new(FADE, Enum.EasingStyle.Linear),
					{ Volume = 1 }
				):Play()

				if previous then
					fadeOut(previous)
				end

				if sound.Looped then
					-- Tek parça: sonsuza kadar döner, bekleyecek bir son yok
					return
				end

				--[[
					Parçanın bitmesini bekliyoruz. Ended gelmezse (ses
					yüklenemediyse) sonsuza kadar beklememek için bir üst
					sınır da var.
				]]
				local finished = false
				sound.Ended:Once(function()
					finished = true
				end)

				local waited = 0
				while not finished and not stopped and playToken == token and waited < 600 do
					task.wait(0.5)
					waited += 0.5
				end

				if playToken ~= token or stopped then
					return
				end
			end
		end)
	end

	--[[
		Bölge değişimini izliyoruz. Saniyede bir yeter: bölge geçişi
		yürüyerek oluyor ve bir saniyelik gecikme fark edilmiyor.
	]]
	local elapsed = 0
	local connection = RunService.Heartbeat:Connect(function(delta)
		if stopped then
			return
		end

		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end

		local zone = zoneOf(root.Position)
		if zone ~= currentZone then
			playZone(zone)
		end
	end)

	return {
		SetDucked = function(value: boolean)
			if ducked == value then
				return
			end
			ducked = value
			fadeGroup(targetVolume())
		end,
		Stop = function()
			stopped = true
			playToken += 1
			connection:Disconnect()
			if current then
				fadeOut(current)
				current = nil
			end
		end,
	}
end

return Music
