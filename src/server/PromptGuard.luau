--!strict
-- ProximityPrompt tetiklemelerinin sunucu tarafında doğrulanması.
--
-- ProximityPrompt güvenilir değildir. Exploit araçları `fireproximityprompt`
-- ile Triggered olayını istedikleri mesafeden, tuşa hiç basmadan ve
-- HoldDuration'ı beklemeden ateşleyebilir. İstemcide görünen mesafe halkası
-- ve dolan çember tamamen istemci tarafıdır; sunucu bunların hiçbirini
-- kendiliğinden doğrulamaz.
--
-- Bu oyunda etkisi büyük: doğrulama olmadan bir oyuncu rakip üsse hiç
-- gitmeden haritanın öbür ucundan karakter çalabilir ve 3 saniyelik
-- basılı tutmayı atlayabilir. Çalmanın bütün riski yürümekte olduğu için
-- bu, oyunun dengesini tamamen bozar.
--
-- Guard iki şeyi sunucu tarafında zorunlu kılar:
--   1. Oyuncu gerçekten promptun yakınında mı
--   2. Tuşu gerçekten yeterince basılı tuttu mu

local PromptGuard = {}

-- Ağ gecikmesi ve karakter hareketi için pay. Çok dar tutarsak yüksek
-- ping'li normal oyuncular reddedilir.
local DISTANCE_TOLERANCE = 6
local HOLD_TOLERANCE = 0.4

-- Basılı tutma tamamlandıktan sonra tetikleme bu süre içinde gelmeli.
-- Kayıt silinmeden bırakıldığı için (aşağıya bak) eski bir basışın
-- sonradan yeniden kullanılmasını bu engelliyor.
local HOLD_FRESHNESS = 3

-- Tanı için: true yapılırsa her olay Output'a yazılır.
PromptGuard.Debug = false

type HoldRecord = { began: number, ended: number? }

-- prompt -> oyuncu -> basış kaydı
local holds: { [ProximityPrompt]: { [Player]: HoldRecord } } = {}

-- Motor bu olayları sunucuya hiç göndermiyorsa basılı tutma kontrolünü
-- zorlayamayız; zorlarsak kimse çalamaz/satamaz. İlk gerçek basışı
-- gördüğümüz anda true olur ve kontrol devreye girer. Görmediğimiz
-- sürece mesafe kontrolüyle yetiniyoruz — oyunu kilitlemek, bir
-- exploit'i açık bırakmaktan daha kötü.
local holdEventsSeen = false
local warnedOnce = false

local function log(...)
	if PromptGuard.Debug then
		print("[PromptGuard]", ...)
	end
end

--[[
	Promptu izlemeye alır. Prompt oluşturulduktan hemen sonra çağrılmalı,
	yoksa basılı tutma bilgisi toplanmaz ve her tetikleme reddedilir.
]]
function PromptGuard.Watch(prompt: ProximityPrompt)
	holds[prompt] = {}

	prompt.PromptButtonHoldBegan:Connect(function(player)
		holdEventsSeen = true

		local record = holds[prompt]
		if record then
			record[player] = { began = os.clock() }
			log("HoldBegan", prompt.Name, player.Name)
		end
	end)

	-- Kaydı SİLMİYORUZ, sadece bitiş anını işaretliyoruz.
	-- Motor basılı tutma tamamlandığında HoldEnded'ı Triggered'dan önce
	-- gönderiyor; kaydı burada silmek tetiklemeyi dayanaksız bırakıyor
	-- ve meşru oyuncu da reddediliyordu.
	prompt.PromptButtonHoldEnded:Connect(function(player)
		local record = holds[prompt]
		local entry = record and record[player]
		if entry then
			entry.ended = os.clock()
			log("HoldEnded", prompt.Name, player.Name, string.format("%.2f sn", entry.ended - entry.began))
		end
	end)

	prompt.Destroying:Connect(function()
		holds[prompt] = nil
	end)
end

--[[
	Tetiklemenin gerçek olup olmadığını söyler. false dönerse çağıran
	işlemi sessizce bırakmalı — sahte tetiklemeye geri bildirim vermek
	exploit'e yardımcı olur.
]]
function PromptGuard.Validate(prompt: ProximityPrompt, player: Player): boolean
	local anchor = prompt.Parent
	if not (anchor and anchor:IsA("BasePart")) then
		return false
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end

	-- Ölü oyuncu prompt tetikleyemez
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local reach = prompt.MaxActivationDistance + DISTANCE_TOLERANCE
	if (root.Position - anchor.Position).Magnitude > reach then
		return false
	end

	-- HoldDuration sıfırsa basılı tutma diye bir şey yok
	if prompt.HoldDuration <= 0 then
		return true
	end

	if not holdEventsSeen then
		if not warnedOnce then
			warnedOnce = true
			warn("[PromptGuard] Basılı tutma olayları sunucuya ulaşmıyor; "
				.. "sadece mesafe doğrulanıyor.")
		end
		return true
	end

	local record = holds[prompt]
	local entry = record and record[player]
	if not entry then
		log("RED: kayit yok", prompt.Name, player.Name)
		return false
	end

	local now = os.clock()
	local held = (entry.ended or now) - entry.began

	if held < prompt.HoldDuration - HOLD_TOLERANCE then
		log("RED: kisa basis", string.format("%.2f < %.2f", held, prompt.HoldDuration))
		return false
	end

	if now - entry.began > prompt.HoldDuration + HOLD_FRESHNESS then
		log("RED: bayat kayit", string.format("%.2f sn once", now - entry.began))
		return false
	end

	-- Aynı basıştan ikinci tetikleme çıkmasın
	record[player] = nil
	log("KABUL", prompt.Name, player.Name, string.format("%.2f sn tutuldu", held))
	return true
end

--[[
	Promptu izlemeye alır ve doğrulamadan geçen tetiklemelerde handler'ı
	çağırır. Watch + Validate'i tek yerde topladığı için çağıran tarafın
	doğrulamayı atlaması zorlaşıyor.
]]
function PromptGuard.Connect(prompt: ProximityPrompt, handler: (Player) -> ())
	PromptGuard.Watch(prompt)

	prompt.Triggered:Connect(function(player)
		if PromptGuard.Validate(prompt, player) then
			handler(player)
		end
	end)
end

return PromptGuard
