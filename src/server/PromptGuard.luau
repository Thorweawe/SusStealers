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
local HOLD_TOLERANCE = 0.25

-- prompt -> oyuncu -> tuşa basmaya başladığı an
local holdStart: { [ProximityPrompt]: { [Player]: number } } = {}

--[[
	Promptu izlemeye alır. Prompt oluşturulduktan hemen sonra çağrılmalı,
	yoksa basılı tutma bilgisi toplanmaz ve her tetikleme reddedilir.
]]
function PromptGuard.Watch(prompt: ProximityPrompt)
	holdStart[prompt] = {}

	prompt.PromptButtonHoldBegan:Connect(function(player)
		local record = holdStart[prompt]
		if record then
			record[player] = os.clock()
		end
	end)

	prompt.PromptButtonHoldEnded:Connect(function(player)
		local record = holdStart[prompt]
		if record then
			record[player] = nil
		end
	end)

	prompt.Destroying:Connect(function()
		holdStart[prompt] = nil
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
	if prompt.HoldDuration > 0 then
		local record = holdStart[prompt]
		local started = record and record[player]
		if not started then
			return false
		end

		if os.clock() - started < prompt.HoldDuration - HOLD_TOLERANCE then
			return false
		end

		-- Aynı basıştan ikinci kez tetikleme çıkmasın
		record[player] = nil
	end

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
