-- Anamol Hub v1.0 | Rayfield Gen2 UI | Flick executor
-- Faithful port of the Flick custom-UI build: same key system + same
-- combat/ESP core, UI moved to Rayfield Gen2.
-- Docs: https://docs.sirius.menu/rayfield-gen2/getting-started

if Instance == nil or game == nil or typeof(game.GetService) ~= "function" then
	error("not a main executor context")
end

local players = game:GetService("Players")
local rs = game:GetService("RunService")
local uis = game:GetService("UserInputService")
local user_input_service = uis
local ws = game:GetService("Workspace")
local gsvc = game:GetService("GuiService")
local rep = game:GetService("ReplicatedStorage")
local lp = players.LocalPlayer
repeat task.wait() until ws.CurrentCamera

local task_wait = task.wait
local task_spawn = task.spawn
local task_delay = task.delay
local unpack_fn = table.unpack or unpack
local _env = (typeof(getgenv) == "function" and getgenv()) or {}
local openbrowser_g = _env.openbrowser
local setclipboard_g = _env.setclipboard or _env.toclipboard

local Rayfield
do
	local ok, res = pcall(function()
		return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
	end)
	if not ok or res == nil then
		error("failed to load Rayfield Gen2")
	end
	Rayfield = res
end

-- // Consts (kept from custom-UI build) // --
local LOGO = "rbxassetid://128018839449849"
-- Documented Gen2 tab icon. The sidebar rail is icon-led, so name-only
-- tabs render as blank rows; every tab below carries this icon.
local TAB_ICON = 93364949241311
local SKEY = "ANAMOLHUBSCRIPTSARETHEBEST"
local DURL = "https://discord.gg/rhJCCGquuW"
local DCODE = "rhJCCGquuW"
local PREM = {}
PREM["ANAMOLHUBPREMIUMFOREVER"] = true
local AFILE = "anamol_auth.txt"
local NTTL = 86400
local PTTL = 2592000

-- // Auth state // --
local authed = false
local auth_exp = 0
local auth_prem = false
local auth_key = ""
local unloaded = false

-- // Config (same defaults as custom-UI build) // --
local Config = {}
Config.Combat = {Aimbot = false, SilentAim = false, Triggerbot = false, ShowFOV = true, Smoothness = 8, FOVSize = 120, WalkSpeed = 16, TriggerDelay = 0.06}
Config.ESP = {Enabled = false, Box = true, Name = true, Distance = true, Health = true, Tracer = false, MaxDistance = 2000}
Config.Shared = {TeamCheck = false}

-- // Key helpers (unchanged logic) // --
local function trim(s)
	if typeof(s) ~= "string" then
		return ""
	end
	local r = string.gsub(s, "^%s+", "")
	r = string.gsub(r, "%s+$", "")
	return r
end

-- Bot keys are checksummed (ANML-XXXXXX-XXXXXX: 10 payload + 2 check
-- chars, A-Z0-9, case-insensitive) so random text is rejected.
local KEY_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local function keyval(ch)
	local i = string.find(KEY_ALPHA, ch, 1, true)
	return i and (i - 1) or nil
end
local function botkey_ok(k)
	k = string.upper(trim(k))
	local p1, p2 = string.match(k, "^ANML%-(%w%w%w%w%w%w)%-(%w%w%w%w%w%w)$")
	if not p1 then
		return false
	end
	local all = p1 .. p2
	for i = 1, 12 do
		if not keyval(string.sub(all, i, i)) then
			return false
		end
	end
	-- reject trivial payloads (e.g. all same char) — guessable otherwise
	local same = true
	for i = 2, 10 do
		if string.sub(all, i, i) ~= string.sub(all, 1, 1) then
			same = false
			break
		end
	end
	if same then
		return false
	end
	local sum = 0
	for i = 1, 10 do
		sum = sum + keyval(string.sub(all, i, i)) * (i * 7 + 3)
	end
	local want = sum % 1296
	local got = keyval(string.sub(all, 11, 11)) * 36 + keyval(string.sub(all, 12, 12))
	return got == want
end

local function keykind(k)
	k = trim(k)
	if k == SKEY then
		return "master"
	end
	if PREM[k] then
		return "prem"
	end
	if botkey_ok(k) then
		return "bot"
	end
	return nil
end

local function save_auth(k, prem)
	if typeof(writefile) ~= "function" then
		return
	end
	auth_exp = os.time() + (prem and PTTL or NTTL)
	auth_prem = prem
	auth_key = k
	pcall(function()
		writefile(AFILE, k .. "\n" .. tostring(auth_exp) .. "\n" .. tostring(lp.UserId))
	end)
end

local function load_auth()
	if typeof(isfile) ~= "function" or typeof(readfile) ~= "function" then
		return nil
	end
	local ok, has = pcall(function() return isfile(AFILE) end)
	if not ok or not has then
		return nil
	end
	local ok2, d = pcall(function() return readfile(AFILE) end)
	if not ok2 or typeof(d) ~= "string" then
		return nil
	end
	local L = {}
	for l in string.gmatch(d, "[^\r\n]+") do
		table.insert(L, trim(l))
	end
	if #L < 2 then
		return nil
	end
	local exp = tonumber(L[2])
	if not exp or exp <= os.time() then
		pcall(function()
			if typeof(delfile) == "function" then
				delfile(AFILE)
			end
		end)
		return nil
	end
	local k = L[1]
	local kind = keykind(k)
	if kind == nil then
		return nil
	end
	auth_exp = exp
	auth_prem = (kind == "prem")
	auth_key = k
	return k
end

local function delete_key()
	pcall(function()
		if typeof(isfile) == "function" and typeof(delfile) == "function" then
			if isfile(AFILE) then
				delfile(AFILE)
			end
		end
	end)
	authed = false
	auth_exp = 0
	auth_prem = false
	auth_key = ""
end

local function copy_discord()
	if typeof(setclipboard_g) == "function" then
		pcall(function() setclipboard_g(DURL) end)
	end
	pcall(function() gsvc:OpenBrowserWindow(DURL) end)
	if typeof(openbrowser_g) == "function" then
		pcall(function() openbrowser_g(DURL) end)
	end
end

local function apply_walkspeed(v)
	local ch = lp.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	if h then
		pcall(function() h.WalkSpeed = v end)
	end
end

lp.CharacterAdded:Connect(function()
	task_delay(0.5, function()
		if authed and not unloaded then
			apply_walkspeed(Config.Combat.WalkSpeed)
		end
	end)
end)

-- // Combat / ESP core (same behavior as custom-UI build) // --
local fov = nil
if typeof(Drawing) == "table" and typeof(Drawing.new) == "function" then
	fov = Drawing.new("Circle")
	fov.Thickness = 1.5
	fov.Color = Color3.fromRGB(255, 255, 255)
	fov.Transparency = 0.35
	fov.Filled = false
	fov.NumSides = 64
	fov.Visible = false
end

local render_camera = ws.CurrentCamera
local last_trigger = 0

local function istm(p)
	if Config.Shared.TeamCheck == false then
		return false
	end
	if p == lp then
		return true
	end
	local a, b = lp.Team, p.Team
	if a == nil or b == nil then
		return false
	end
	return a == b
end

local function parts(p)
	local c = p.Character
	if not c then
		return nil, nil
	end
	local h = c:FindFirstChild("Head")
	local m = c:FindFirstChildOfClass("Humanoid")
	if not h or not m or m.Health <= 0 then
		return nil, nil
	end
	return h, m
end

local function silent_tgt()
	local c = ws.CurrentCamera
	if not c then
		return nil
	end
	local v = c.ViewportSize
	local x, y = v.X * 0.5, v.Y * 0.5
	local b, d = nil, 1e9
	for _, p in ipairs(players:GetPlayers()) do
		if p ~= lp and not istm(p) then
			local h = parts(p)
			if h then
				local s, o = c:WorldToViewportPoint(h.Position)
				if o then
					local dd = math.sqrt((s.X - x) ^ 2 + (s.Y - y) ^ 2)
					if dd < d then
						d = dd
						b = h
					end
				end
			end
		end
	end
	return b
end

local function aim_tgt()
	local c = ws.CurrentCamera
	if not c then
		return nil, nil, nil
	end
	local v = c.ViewportSize
	local x, y = v.X * 0.5, v.Y * 0.5
	local bh, bp, bd = nil, nil, Config.Combat.FOVSize
	for _, p in ipairs(players:GetPlayers()) do
		if p ~= lp and not istm(p) then
			local h = parts(p)
			if h then
				local s, o = c:WorldToViewportPoint(h.Position)
				if o then
					local dd = math.sqrt((s.X - x) ^ 2 + (s.Y - y) ^ 2)
					if dd <= Config.Combat.FOVSize and dd < bd then
						bd = dd
						bh = h
						bp = p
					end
				end
			end
		end
	end
	return bh, bp, bd
end

local function held()
	if not authed then
		return false
	end
	local o, d = pcall(function() return user_input_service:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) end)
	if o and d then
		return true
	end
	local o2, a = pcall(function() return user_input_service:IsKeyDown(Enum.KeyCode.LeftAlt) end)
	return o2 and a
end

local function doClick()
	if typeof(mouse1click) == "function" then
		pcall(mouse1click)
	elseif typeof(mouse1press) == "function" and typeof(mouse1release) == "function" then
		pcall(function()
			mouse1press()
			task_delay(0.03, function() pcall(mouse1release) end)
		end)
	end
end

local has_h = typeof(hookfunction) == "function"
local has_n = typeof(newcclosure) == "function"
local has_c = typeof(checkcaller) == "function"
local cs_r = nil
local cs_o = nil
local bl_o = nil

local function apfw(t)
	if not Config.Combat.SilentAim or not authed then
		return
	end
	if typeof(t) ~= "table" then
		return
	end
	if not t.Origin or not t.Misc then
		return
	end
	local h = silent_tgt()
	if not h then
		return
	end
	local c = ws.CurrentCamera
	if not c then
		return
	end
	if typeof(t.Origin) ~= "Vector3" then
		return
	end
	t.Direction = (h.Position - t.Origin).Unit
	t.Misc.Spread = 0
	t.Misc.CamCFrame = CFrame.lookAt(c.CFrame.Position, h.Position)
end

local function rw(args, n)
	if not Config.Combat.SilentAim or not authed then
		return args
	end
	local h = silent_tgt()
	if not h then
		return args
	end
	local c = ws.CurrentCamera
	if not c then
		return args
	end
	local ci = nil
	for i = 1, n do
		if typeof(args[i]) == "CFrame" then
			ci = i
			break
		end
	end
	if not ci then
		return args
	end
	local pi = nil
	local ii = nil
	for i = ci + 1, n do
		if typeof(args[i]) == "Vector3" and not pi then
			pi = i
		end
		if typeof(args[i]) == "Instance" and not ii then
			ii = i
		end
	end
	if typeof(args[2]) == "number" then
		args[2] = 0
	end
	args[ci] = CFrame.lookAt(c.CFrame.Position, h.Position)
	if pi then
		args[pi] = h.Position
	end
	if ii then
		args[ii] = h
	end
	return args
end

local function hook_b()
	if not has_h or bl_o then
		return
	end
	local ok, bh = pcall(function() return rep.ModuleScripts.GunModules.BulletHandler end)
	if not ok or not bh then
		return
	end
	local ok2, m = pcall(require, bh)
	if not ok2 or not m or typeof(m.Fire) ~= "function" then
		return
	end
	local tf = m.Fire
	local function hk(...)
		local n = select("#", ...)
		local a = {...}
		if has_c and checkcaller() then
			return bl_o(unpack_fn(a, 1, n))
		end
		local ft = n == 1 and a[1] or a[2]
		pcall(apfw, ft)
		return bl_o(unpack_fn(a, 1, n))
	end
	local f = hk
	if has_n then
		local o, c2 = pcall(newcclosure, hk)
		if o and c2 then
			f = c2
		end
	end
	local o, r = pcall(hookfunction, tf, f)
	if o and r then
		bl_o = r
	end
end

local function hook_s()
	if not has_h or cs_o then
		return
	end
	local ok, f = pcall(function() return lp:WaitForChild("ClientRemotes") end)
	if not ok or not f then
		return
	end
	local ok2, r = pcall(function() return f:WaitForChild("CheckShot") end)
	if not ok2 or not r then
		return
	end
	cs_r = r
	local ok3, m = pcall(function() return r.FireServer end)
	if not ok3 or not m then
		return
	end
	local function hk(self, ...)
		local n = select("#", ...)
		local a = {...}
		if has_c and checkcaller() then
			return cs_o(self, unpack_fn(a, 1, n))
		end
		if self ~= cs_r then
			return cs_o(self, unpack_fn(a, 1, n))
		end
		return cs_o(self, unpack_fn(rw(a, n), 1, n))
	end
	local f2 = hk
	if has_n then
		local o, c2 = pcall(newcclosure, hk)
		if o and c2 then
			f2 = c2
		end
	end
	local o, r2 = pcall(hookfunction, m, f2)
	if o and r2 then
		cs_o = r2
	end
end

local pool = {}
local function esp_e(p)
	if typeof(Drawing) ~= "table" or typeof(Drawing.new) ~= "function" then
		return nil
	end
	local e = pool[p]
	if e then
		return e
	end
	e = {}
	e.box = Drawing.new("Square")
	e.box.Thickness = 1
	e.box.Filled = false
	e.box.Color = Color3.fromRGB(240, 240, 248)
	e.name = Drawing.new("Text")
	e.name.Size = 13
	e.name.Center = true
	e.name.Outline = true
	e.name.Color = Color3.fromRGB(238, 238, 244)
	e.dist = Drawing.new("Text")
	e.dist.Size = 12
	e.dist.Center = true
	e.dist.Outline = true
	e.dist.Color = Color3.fromRGB(150, 150, 160)
	e.hp = Drawing.new("Line")
	e.hp.Thickness = 2
	e.tracer = Drawing.new("Line")
	e.tracer.Thickness = 1
	e.tracer.Transparency = 0.35
	e.tracer.Color = Color3.fromRGB(255, 255, 255)
	pool[p] = e
	return e
end

local function esp_h(e)
	if e then
		e.box.Visible = false
		e.name.Visible = false
		e.dist.Visible = false
		e.hp.Visible = false
		e.tracer.Visible = false
	end
end

players.PlayerRemoving:Connect(function(p)
	local e = pool[p]
	if e then
		pcall(function() e.box:Remove() end)
		pcall(function() e.name:Remove() end)
		pcall(function() e.dist:Remove() end)
		pcall(function() e.hp:Remove() end)
		pcall(function() e.tracer:Remove() end)
		pool[p] = nil
	end
end)

local function unload_all(mainWindow)
	if unloaded then
		return
	end
	unloaded = true
	pcall(function() rs:UnbindFromRenderStep("AnamolRender") end)
	if fov then
		pcall(function()
			fov.Visible = false
			fov:Remove()
		end)
		fov = nil
	end
	for p, e in pairs(pool) do
		esp_h(e)
		pcall(function() e.box:Remove() end)
		pcall(function() e.name:Remove() end)
		pcall(function() e.dist:Remove() end)
		pcall(function() e.hp:Remove() end)
		pcall(function() e.tracer:Remove() end)
		pool[p] = nil
	end
	if mainWindow then
		pcall(function() mainWindow:Unload() end)
	end
end

local render_started = false
local function start_render()
	if render_started then
		return
	end
	render_started = true
	rs:BindToRenderStep("AnamolRender", Enum.RenderPriority.Camera.Value + 1, function()
		if not authed or unloaded then
			if fov then
				fov.Visible = false
			end
			return
		end
		if ws.CurrentCamera ~= render_camera then
			render_camera = ws.CurrentCamera
		end
		local cam = ws.CurrentCamera
		if not cam then
			return
		end
		-- FOV circle --
		if Config.Combat.ShowFOV and fov then
			local v = cam.ViewportSize
			fov.Position = Vector2.new(v.X * 0.5, v.Y * 0.5)
			fov.Radius = Config.Combat.FOVSize
			fov.Visible = true
		elseif fov then
			fov.Visible = false
		end
		-- Aimbot (RMB / LeftAlt hold) --
		if Config.Combat.Aimbot and held() then
			local h = aim_tgt()
			if h then
				cam.CFrame = cam.CFrame:Lerp(CFrame.lookAt(cam.CFrame.Position, h.Position), math.clamp(1 / math.max(1, Config.Combat.Smoothness), 0.05, 1))
			end
		end
		-- Triggerbot: toggle existed in config but had no body originally;
		-- minimal impl: click when target sits at crosshair, gated by TriggerDelay.
		-- Executor click only, no game services touched.
		if Config.Combat.Triggerbot then
			local _, _, bd = aim_tgt()
			if bd and bd <= 14 then
				local now = os.clock()
				if now - last_trigger >= (tonumber(Config.Combat.TriggerDelay) or 0.06) then
					last_trigger = now
					doClick()
				end
			end
		end
		-- ESP (Drawing only, same visuals as custom-UI build) --
		if Config.ESP.Enabled and typeof(Drawing) == "table" and typeof(Drawing.new) == "function" then
			local vp = cam.ViewportSize
			local bottom = Vector2.new(vp.X * 0.5, vp.Y)
			for _, p in ipairs(players:GetPlayers()) do
				if p == lp or istm(p) then
					local s = pool[p]
					if s then
						esp_h(s)
					end
				else
					local h, m = parts(p)
					local e = esp_e(p)
					if not h or not e then
						if e then
							esp_h(e)
						end
					else
						local d = (h.Position - cam.CFrame.Position).Magnitude
						if d > Config.ESP.MaxDistance then
							esp_h(e)
						else
							local s, o = cam:WorldToViewportPoint(h.Position)
							if not o then
								esp_h(e)
							else
								local sc = 1000 / math.max(1, d)
								local w = math.clamp(sc * 0.6, 20, 120)
								local hh = math.clamp(sc * 1.1, 30, 200)
								local bp = Vector2.new(s.X - w * 0.5, s.Y - hh * 0.5)
								e.box.Visible = Config.ESP.Box
								e.box.Position = bp
								e.box.Size = Vector2.new(w, hh)
								e.name.Visible = Config.ESP.Name
								e.name.Position = Vector2.new(s.X, bp.Y - 14)
								e.name.Text = p.Name
								e.dist.Visible = Config.ESP.Distance
								e.dist.Position = Vector2.new(s.X, bp.Y + hh + 2)
								e.dist.Text = string.format("%d m", math.floor(d))
								local fr = math.clamp(m.Health / math.max(1, m.MaxHealth), 0, 1)
								e.hp.Visible = Config.ESP.Health
								e.hp.From = Vector2.new(bp.X - 4, bp.Y + hh * (1 - fr))
								e.hp.To = Vector2.new(bp.X - 4, bp.Y + hh)
								e.hp.Color = Color3.fromRGB(math.floor(255 * (1 - fr)), math.floor(255 * fr), 40)
								e.tracer.Visible = Config.ESP.Tracer
								e.tracer.From = bottom
								e.tracer.To = Vector2.new(s.X, bp.Y + hh * 0.5)
							end
						end
					end
				end
			end
		else
			for _, e in pairs(pool) do
				esp_h(e)
			end
		end
	end)
end

-- // Rayfield UI // --
local mainWindow = nil

local function notify(title, content)
	if mainWindow and not mainWindow.unloaded then
		pcall(function()
			mainWindow:Notify({ title = title, content = content })
		end)
	end
end

local function plan_text()
	if not authed then
		return "Locked", "--"
	end
	local plan = auth_prem and "PRO" or "Free"
	local rem = math.max(0, auth_exp - os.time())
	local body = ("Plan: %s\nValid until: %s\nTime left: %dd %dh"):format(
		plan,
		os.date("%b %d, %Y", auth_exp),
		math.floor(rem / 86400),
		math.floor(rem % 86400 / 3600)
	)
	return plan, body
end

local function build_main()
	hook_b()
	hook_s()
	start_render()

	mainWindow = Rayfield:CreateWindow({
		name = "Anamol Hub",
		subtitle = "v1.0 | Flick",
		icon = LOGO,
		sidebarLayout = true,
		showName = "Anamol Hub",
		configuration = {
			autoSave = true,
			autoLoad = true,
			fileName = "AnamolHub-v1",
		},
	})

	pcall(function() mainWindow:CreateTag({ text = "v1.0" }) end)
	pcall(function() mainWindow:CreateTag({ text = auth_prem and "PRO" or "Free" }) end)

	-- Home (Overview / Account from custom-UI build) --
	mainWindow:CreateSection({ name = "General" })
	local home = mainWindow:CreateTab({ name = "Home", icon = TAB_ICON })
	home:CreateSection({ name = "Overview" })
	local plan, body = plan_text()
	local rem_h = math.floor(math.max(0, auth_exp - os.time()) / 3600)
	home:CreateText({
		name = ("@%s (%s)"):format(lp.Name, lp.DisplayName),
		text = body .. ("\nID %d\nKey: %s (%dh left)"):format(lp.UserId, (auth_key ~= "" and auth_key or "No key"), rem_h),
	})
	home:CreateDivider()
	home:CreateButton({
		name = "Copy Key",
		description = "Copy your current key to clipboard.",
		callback = function()
			if typeof(setclipboard_g) == "function" and auth_key ~= "" then
				pcall(function() setclipboard_g(auth_key) end)
				notify("Key copied", "Your key is on the clipboard.")
			else
				notify("No key", "No key loaded to copy.")
			end
		end,
	})
	home:CreateButton({
		name = "Discord",
		description = "Copy invite and open discord.gg/rhJCCGquuW.",
		callback = function()
			copy_discord()
			notify("Discord", "Invite copied. Get your key from the bot.")
		end,
	})
	home:CreateButton({
		name = "Delete Key / Lock Hub",
		description = "Deletes local key file and unloads the hub.",
		callback = function()
			delete_key()
			notify("Locked", "Key deleted. Re-execute to unlock again.")
			task_delay(0.4, function()
				unload_all(mainWindow)
			end)
		end,
	})

	-- Script -> Combat (same rows as custom-UI render_cat "Combat") --
	mainWindow:CreateSection({ name = "Features" })
	local combat = mainWindow:CreateTab({ name = "Combat", icon = TAB_ICON })
	combat:CreateSection({ name = "Aimbot" })
	combat:CreateToggle({
		name = "Aimbot",
		description = "Hold RMB (or LeftAlt) to lock onto head.",
		value = Config.Combat.Aimbot,
		flag = "Combat_Aimbot",
		callback = function(v) Config.Combat.Aimbot = v end,
	})
	combat:CreateToggle({
		name = "Silent Aim",
		description = "Redirects BulletHandler / CheckShot to head.",
		value = Config.Combat.SilentAim,
		flag = "Combat_SilentAim",
		callback = function(v) Config.Combat.SilentAim = v end,
	})
	combat:CreateToggle({
		name = "Triggerbot",
		description = "Clicks when a target sits at crosshair.",
		value = Config.Combat.Triggerbot,
		flag = "Combat_Triggerbot",
		callback = function(v) Config.Combat.Triggerbot = v end,
	})
	combat:CreateToggle({
		name = "Show FOV",
		value = Config.Combat.ShowFOV,
		flag = "Combat_ShowFOV",
		callback = function(v) Config.Combat.ShowFOV = v end,
	})
	combat:CreateToggle({
		name = "Team Check",
		value = Config.Shared.TeamCheck,
		flag = "Shared_TeamCheck",
		callback = function(v) Config.Shared.TeamCheck = v end,
	})
	combat:CreateDivider({ text = "tuning" })
	combat:CreateSlider({
		name = "Smoothness",
		range = { 1, 20 },
		increment = 1,
		value = Config.Combat.Smoothness,
		flag = "Combat_Smoothness",
		callback = function(v) Config.Combat.Smoothness = v end,
	})
	combat:CreateSlider({
		name = "FOV Size",
		range = { 40, 400 },
		increment = 1,
		value = Config.Combat.FOVSize,
		suffix = "px",
		flag = "Combat_FOVSize",
		callback = function(v) Config.Combat.FOVSize = v end,
	})
	combat:CreateSlider({
		name = "Trigger Delay",
		range = { 0, 50 },
		increment = 1,
		value = math.floor((Config.Combat.TriggerDelay or 0.06) * 100 + 0.5),
		suffix = "cs",
		flag = "Combat_TriggerDelayCs",
		callback = function(v) Config.Combat.TriggerDelay = v / 100 end,
	})

	-- Script -> Visuals (same rows as custom-UI render_cat fallback) --
	local visuals = mainWindow:CreateTab({ name = "ESP", icon = TAB_ICON })
	visuals:CreateSection({ name = "Display" })
	visuals:CreateToggle({
		name = "Enabled",
		value = Config.ESP.Enabled,
		flag = "ESP_Enabled",
		callback = function(v) Config.ESP.Enabled = v end,
	})
	visuals:CreateToggle({
		name = "Box",
		value = Config.ESP.Box,
		flag = "ESP_Box",
		callback = function(v) Config.ESP.Box = v end,
	})
	visuals:CreateToggle({
		name = "Name",
		value = Config.ESP.Name,
		flag = "ESP_Name",
		callback = function(v) Config.ESP.Name = v end,
	})
	visuals:CreateToggle({
		name = "Distance",
		value = Config.ESP.Distance,
		flag = "ESP_Distance",
		callback = function(v) Config.ESP.Distance = v end,
	})
	visuals:CreateToggle({
		name = "Health",
		value = Config.ESP.Health,
		flag = "ESP_Health",
		callback = function(v) Config.ESP.Health = v end,
	})
	visuals:CreateToggle({
		name = "Tracer",
		value = Config.ESP.Tracer,
		flag = "ESP_Tracer",
		callback = function(v) Config.ESP.Tracer = v end,
	})
	visuals:CreateDivider({ text = "range" })
	visuals:CreateSlider({
		name = "Max Distance",
		range = { 50, 2000 },
		increment = 10,
		value = Config.ESP.MaxDistance,
		suffix = "m",
		flag = "ESP_MaxDistance",
		callback = function(v) Config.ESP.MaxDistance = v end,
	})

	-- Script -> Movement (same row as custom-UI render_cat "Movement") --
	local movement = mainWindow:CreateTab({ name = "Movement", icon = TAB_ICON })
	movement:CreateSection({ name = "Player" })
	movement:CreateSlider({
		name = "Walk Speed",
		range = { 16, 120 },
		increment = 1,
		value = Config.Combat.WalkSpeed,
		flag = "Combat_WalkSpeed",
		callback = function(v)
			Config.Combat.WalkSpeed = v
			apply_walkspeed(v)
		end,
	})

	-- Settings --
	mainWindow:CreateSection({ name = "System" })
	local settings = mainWindow:CreateTab({ name = "Settings", icon = TAB_ICON })
	settings:CreateSection({ name = "Interface" })
	settings:CreateKeybind({
		name = "Toggle UI",
		description = "Show / hide the hub (RightShift).",
		value = Enum.KeyCode.RightShift,
		flag = "UI_ToggleKey",
		callback = function()
			if mainWindow and not mainWindow.unloaded then
				mainWindow:ToggleHide()
			end
		end,
	})
	settings:CreateKeybind({
		name = "Menu Key",
		description = "Second key to show / hide the hub (Insert).",
		value = Enum.KeyCode.Insert,
		flag = "UI_MenuKey",
		callback = function()
			if mainWindow and not mainWindow.unloaded then
				mainWindow:ToggleHide()
			end
		end,
	})
	settings:CreateDivider({ text = "theme" })
	settings:CreateButton({
		name = "Theme: Default",
		callback = function() mainWindow:ChangeTheme("default") end,
	})
	settings:CreateButton({
		name = "Theme: Cobalt",
		callback = function() mainWindow:ChangeTheme("cobalt") end,
	})
	settings:CreateButton({
		name = "Theme: Ember",
		callback = function() mainWindow:ChangeTheme("ember") end,
	})
	settings:CreateDivider({ text = "danger" })
	settings:CreateButton({
		name = "Unload Hub",
		description = "Unbind render loop, clear ESP and destroy UI.",
		callback = function()
			notify("Unloading", "Anamol Hub closed.")
			task_delay(0.3, function()
				unload_all(mainWindow)
			end)
		end,
	})

	authed = true
	apply_walkspeed(Config.Combat.WalkSpeed)
	notify("Anamol Hub v1.0", ("Welcome, %s (%s plan)."):format(lp.DisplayName, plan))
end

local function build_auth()
	local authWindow = Rayfield:CreateWindow({
		name = "Anamol Hub",
		subtitle = "v1.0 | Key System",
		icon = LOGO,
		sidebarLayout = false,
		showName = "Anamol Hub",
	})

	local keyTab = authWindow:CreateTab({ name = "Key", icon = TAB_ICON })
	keyTab:CreateSection({ name = "Authentication" })
	keyTab:CreateText({
		name = "Enter your key",
		text = "Paste the key from the Discord bot, then Unlock. Keys persist locally until expiry.",
	})

	local status = keyTab:CreateText({ name = "Status", text = "Waiting for key..." })
	local pending = ""

	local keyInput = keyTab:CreateInput({
		name = "Key",
		placeholder = "Paste key from bot...",
		value = "",
		callback = function(text)
			pending = text or ""
			local k = trim(pending)
			if k == "" then
				return
			end
			local kind = keykind(k)
			if kind == nil then
				status:Set("Wrong key - use bot key.")
				return
			end
			save_auth(k, kind == "prem")
			authWindow:Notify({ title = "Verified", content = "Loading Anamol Hub..." })
			task_delay(0.3, function()
				pcall(function() authWindow:Unload() end)
				build_main()
			end)
		end,
	})

	keyTab:CreateButton({
		name = "Unlock",
		description = "Verify the pasted key.",
		callback = function()
			local k = trim((keyInput and keyInput.value) or pending)
			if k == "" then
				status:Set("Paste a bot key first.")
				return
			end
			local kind = keykind(k)
			if kind == nil then
				status:Set("Wrong key - use bot key.")
				return
			end
			save_auth(k, kind == "prem")
			authWindow:Notify({ title = "Verified", content = "Loading Anamol Hub..." })
			task_delay(0.3, function()
				pcall(function() authWindow:Unload() end)
				build_main()
			end)
		end,
	})

	keyTab:CreateButton({
		name = "Get Key",
		description = "Copies discord.gg/rhJCCGquuW and opens it.",
		callback = function()
			copy_discord()
			status:Set("Discord invite copied - get a key from the bot.")
			authWindow:Notify({ title = "Discord", content = "Invite copied. Get your key from the bot." })
		end,
	})
end

-- // Boot: same persisted-key fast path as custom-UI build // --
task_spawn(function()
	task_wait(0.3)
	if unloaded then
		return
	end
	local s = load_auth()
	if s ~= nil then
		build_main()
	else
		build_auth()
	end
end)
