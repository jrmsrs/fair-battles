return function(mod)
  -- ==========================================================================
  -- MOD OPTIONS
  -- ==========================================================================
  -- Defines the customizable settings available in the game's Mod Manager.
  mod.options:define({
    {
      key = "fair_battle",
      type = "toggle",
      label = "FAIR BATTLE",
        default = true
    },
    {
      key = "selection_mode",
      type = "choice",
      label = "SELECTION",
      choices = {
        { "Top Down", "top_down" },
        { "Dynamic", "dynamic" },
        { "Draft", "draft" }
      },
      default = "top_down"
    }
  })

  -- State tracker for the currently active battle context.
  local current_match = nil

  -- ==========================================================================
  -- HELPER FUNCTIONS
  -- ==========================================================================

  -- Checks if a specific value exists within an indexed table.
  local function is_in_table(val, tbl)
    for _, v in ipairs(tbl) do
      if v == val then return true end
    end
    return false
  end

  -- Checks if a specific Pokémon object is currently stored in the benched table.
  local function is_benched(mon, benched_tbl)
    for _, saved in ipairs(benched_tbl) do
      if saved.mon == mon then return true end
    end
    return false
  end

  -- Moves a Pokémon to the bench, saving its original state and applying restrictions.
  local function bench_mon(match, mon)
    -- Save the exact pre-battle state to restore it safely after the match.
    table.insert(match.benched, {
      mon = mon,
      status = mon.status,
      hp = mon.hp,
      original_nickname = mon.nickname
    })
    
    -- Assign the custom "OUT" status and spoof HP to natively block revives.
    mon.status = "OUT"
    if mon.hp <= 0 then mon.hp = 1 end

    -- Applies visual feedback exclusively for Gen 2, as its UI natively ignores custom statuses.
    -- Modifies the nickname while strictly respecting the 10-character limit.
    if match.is_gen2 then
      local game_ref = match.battle.game or mod.game
      local base_name = mon.nickname or (mon.species and game_ref.data.pokemon[mon.species].name) or "PKMN"

      if not string.match(base_name, "^%[X%]") then
        if string.len(base_name) <= 7 then
          mon.nickname = "[X]" .. base_name
        else
          mon.nickname = "[X]" .. string.sub(base_name, 1, 6) .. "."
        end
      end
    end
  end

  -- Evaluates if the dynamic limit has been reached. If so, benches all remaining unsent Pokémon.
  local function check_dynamic_limit(match, party)
    if match.mode == "dynamic" and #match.active >= match.limit and not match.locked then
      match.locked = true
      for i = 1, #party do
        local mon = party[i]
        if not is_in_table(mon, match.active) and not is_benched(mon, match.benched) then
          bench_mon(match, mon)
        end
      end
    end
  end

  -- ==========================================================================
  -- CORE BATTLE INITIALIZATION
  -- ==========================================================================
  mod.events:on("battle.started", function(ev)
    current_match = nil

    if not mod.options:get("fair_battle") then return end
    if ev.kind ~= "trainer" then return end

    local battle = ev.battle
    -- Feature Detection: Differentiates between Gen 1 and Gen 2 engine architectures.
    local is_gen2 = (battle.say == nil) 
    
    local enemy_party = battle.enemyParty
    -- Resolves the correct party reference based on the active generation.
    local player_party = is_gen2 and battle.party or battle.game.save.party

    if not enemy_party or not player_party then return end
    if not is_gen2 and not battle.player then return end

    local enemy_count = #enemy_party
    local player_count = #player_party
    local mode = mod.options:get("selection_mode") or "top_down"

    -- Initialize the global state for the new match.
    current_match = {
      battle = battle,
      active = {},
      benched = {},
      limit = enemy_count,
      mode = mode,
      locked = false,
      initialized = false,
      is_gen2 = is_gen2,
      needs_intro = true 
    }

    local healthy_total = 0
    for _, mon in ipairs(player_party) do
      if mon.hp > 0 and not mon.isEgg then healthy_total = healthy_total + 1 end
    end

    -- ========================================
    -- GEN 2 SPECIFIC INITIALIZATION
    -- ========================================
    if is_gen2 then
      -- Automatically bench Pokémon that are already fainted (except in Draft mode).
      if mode ~= "draft" then
        for i = 1, #player_party do
          local mon = player_party[i]
          if mon.hp <= 0 and not mon.isEgg then
            bench_mon(current_match, mon)
          end
        end
      end
      
      local lead = battle.player
      table.insert(current_match.active, lead)

      -- Gen 2 Top Down Logic
      if mode == "top_down" then
        local active_count = 1
        for i = 1, player_count do
          local mon = player_party[i]
          if mon ~= lead and not is_benched(mon, current_match.benched) and not mon.isEgg then
            if active_count < enemy_count then
              table.insert(current_match.active, mon)
              active_count = active_count + 1
            else
              bench_mon(current_match, mon)
            end
          end
        end
        current_match.locked = true

      -- Gen 2 Dynamic Logic
      elseif mode == "dynamic" then
        check_dynamic_limit(current_match, player_party)
      end

    -- ========================================
    -- GEN 1 SPECIFIC INITIALIZATION
    -- ========================================
    else
      -- Synchronously render rules prior to the battle interface appearing.
      if healthy_total > enemy_count then
        battle:say(string.format("MATCH RULES: %dV%d", enemy_count, enemy_count))
      end

      -- Pre-bench inherently fainted Pokémon.
      for i = 1, #player_party do
        local mon = player_party[i]
        if mon.hp <= 0 then
          bench_mon(current_match, mon)
        end
      end

      -- Utilizes battle:act to defer logic until Turn 1 natively starts,
      -- ensuring compatibility with third-party pre-battle UI mods (e.g., Choose Lead).
      battle:act(function()
        if not current_match or current_match.initialized then return end
        current_match.initialized = true

        local lead = battle.player.mon
        table.insert(current_match.active, lead)

        -- Gen 1 Top Down Logic
        if mode == "top_down" then
          local active_count = 1
          for i = 1, player_count do
            local mon = player_party[i]
            if mon ~= lead and mon.status ~= "OUT" then
              if active_count < enemy_count then
                table.insert(current_match.active, mon)
                active_count = active_count + 1
              else
                bench_mon(current_match, mon)
              end
            end
          end
          current_match.locked = true

        -- Gen 1 Dynamic Logic
        elseif mode == "dynamic" then
          check_dynamic_limit(current_match, player_party)

        -- Gen 1 Draft Logic
        elseif mode == "draft" then
          local draftable_count = 0
          for i = 1, player_count do
            local mon = player_party[i]
            if mon ~= lead and mon.status ~= "OUT" then
              draftable_count = draftable_count + 1
            end
          end

          local picks_needed = enemy_count - 1
          -- Auto-lock and bypass UI if no drafting is necessary.
          if picks_needed <= 0 or draftable_count == 0 then
            for i = 1, player_count do
              local mon = player_party[i]
              if mon ~= lead and mon.status ~= "OUT" then
                bench_mon(current_match, mon)
              end
            end
            current_match.locked = true
          else
            -- Render the Gen 1 Draft UI immediately after the act queue.
            battle:uiNext(function()
              local items = {}
              local current_picks = 0
              local picked_mons = {}
              local draft_menu
              
              for i = 1, player_count do
                local mon = player_party[i]
                if mon ~= lead and mon.status ~= "OUT" then
                  local item = {
                    label = mon.nickname or battle.game.data.pokemon[mon.species].name,
                    right = " ",
                    mon = mon
                  }
                  item.onSelect = function(self_item)
                    if picked_mons[mon] then
                      picked_mons[mon] = nil
                      current_picks = current_picks - 1
                      self_item.right = " "
                    else
                      if current_picks < picks_needed then
                        picked_mons[mon] = true
                        current_picks = current_picks + 1
                        self_item.right = "IN"
                      else
                        require("src.core.Sound").play(battle.game.data, "Denied")
                      end
                    end
                  end
                  table.insert(items, item)
                end
              end
              
              local function encerrar_draft()
                for _, item_mon in ipairs(items) do
                  if item_mon.mon then
                    if picked_mons[item_mon.mon] then
                      table.insert(current_match.active, item_mon.mon)
                    else
                      bench_mon(current_match, item_mon.mon)
                    end
                  end
                end
                current_match.locked = true
                if draft_menu then draft_menu:close() end
              end

              table.insert(items, {
                label = "[ FINISH ]",
                onSelect = function(self_item)
                  if current_picks == picks_needed then
                    encerrar_draft()
                  else
                    require("src.core.Sound").play(battle.game.data, "Denied")
                    local TextBox = require("src.render.TextBox")
                    local missing = picks_needed - current_picks
                    battle.game.stack:push(TextBox.new(battle.game, "Please select\n" .. missing .. " more!"))
                  end
                end
              })

              local function fallback_autofill(menu)
                if not current_match then 
                  if menu then menu:close() end 
                  return 
                end
                for _, item_mon in ipairs(items) do
                  if item_mon.mon then
                    if current_picks < picks_needed and not picked_mons[item_mon.mon] then
                      picked_mons[item_mon.mon] = true
                      current_picks = current_picks + 1
                      table.insert(current_match.active, item_mon.mon)
                    elseif not picked_mons[item_mon.mon] then
                      bench_mon(current_match, item_mon.mon)
                    else
                      if not is_in_table(item_mon.mon, current_match.active) then
                        table.insert(current_match.active, item_mon.mon)
                      end
                    end
                  end
                end
                current_match.locked = true
                if menu then menu:close() end
              end

              draft_menu = mod.ui.ListMenu.new(battle.game, "CHOOSE " .. picks_needed, items, {
                footer = "A:SEL B:AUTOFILL",
                onChoose = function(item)
                  if item.onSelect then item.onSelect(item) end
                end,
                onCancel = function(menu) fallback_autofill(menu) end
              })
              
              return draft_menu
            end)
          end
        end
      end)
    end
  end)

  -- ==========================================================================
  -- UI HOOKS AND INTERCEPTIONS (SCREEN.PUSHED)
  -- ==========================================================================
  mod.events:on("screen.pushed", function(ev)
    local state = ev.state
    if not current_match then return end

    -- ========================================
    -- GEN 2 DRAFT UI AND EVENT QUEUE HOOK
    -- ========================================
    -- Overrides the game's native event queue process to render Draft mode 
    -- seamlessly precisely when the turn interface becomes active.
    if current_match.is_gen2 and state.screenId == "Gen2BattleState" and not state.__fb_queue_hooked then
      state.__fb_queue_hooked = true
      
      local orig_advanceQueue = state.advanceQueue
      state.advanceQueue = function(self)
        local ret = orig_advanceQueue(self)
        
        -- Hook precisely when the battle menu intro concludes.
        if self.phase == "menu" and current_match and not current_match.intro_done then
          current_match.intro_done = true
          
          local player_party = self.battle.party
          local enemy_count = current_match.limit
          local lead = self.battle.player
          
          local healthy_total = 0
          for _, mon in ipairs(player_party) do
            if mon.hp > 0 and not mon.isEgg then healthy_total = healthy_total + 1 end
          end

          if healthy_total > enemy_count then
            if current_match.mode == "draft" then
              local draftable_count = 0
              for i = 1, #player_party do
                local mon = player_party[i]
                if mon ~= lead and not is_benched(mon, current_match.benched) and not mon.isEgg then
                  draftable_count = draftable_count + 1
                end
              end

              local picks_needed = enemy_count - 1
              if picks_needed <= 0 or draftable_count == 0 then
                for i = 1, #player_party do
                  local mon = player_party[i]
                  if mon ~= lead and not is_benched(mon, current_match.benched) and not mon.isEgg then
                    bench_mon(current_match, mon)
                  end
                end
                current_match.locked = true
                self.game.stack:push(require("src.render.TextBox").new(self.game, string.format("MATCH RULES: %dV%d", enemy_count, enemy_count)))
              else
                -- Initialize Gen 2 Draft UI
                local items = {}
                local current_picks = 0
                local picked_mons = {}
                local draft_menu 

                for i = 1, #player_party do
                  local mon = player_party[i]
                  if mon ~= lead and not is_benched(mon, current_match.benched) and not mon.isEgg then
                    -- Visually sanitize the "[X]" hack exclusively for clean menu display.
                    local display_name = string.gsub(mon.nickname or self.game.data.pokemon[mon.species].name or "?", "^%[X%]", "")
                    local item = {
                      label = display_name,
                      right = " ",
                      mon = mon
                    }
                    item.onSelect = function(self_item)
                      if picked_mons[mon] then
                        picked_mons[mon] = nil
                        current_picks = current_picks - 1
                        self_item.right = " "
                      else
                        if current_picks < picks_needed then
                          picked_mons[mon] = true
                          current_picks = current_picks + 1
                          self_item.right = "IN"
                        else
                          require("src.core.Sound").play(self.game.data, "Denied")
                        end
                      end
                    end
                    table.insert(items, item)
                  end
                end

                local function encerrar_draft()
                  for _, item_mon in ipairs(items) do
                    if item_mon.mon then
                      if picked_mons[item_mon.mon] then
                        table.insert(current_match.active, item_mon.mon)
                      else
                        bench_mon(current_match, item_mon.mon)
                      end
                    end
                  end
                  current_match.locked = true
                  if draft_menu then draft_menu:close() end
                end

                table.insert(items, {
                  label = "[ FINISH ]",
                  onSelect = function(self_item)
                    if current_picks == picks_needed then
                      encerrar_draft()
                    else
                      require("src.core.Sound").play(self.game.data, "Denied")
                      self.game.stack:push(require("src.render.TextBox").new(self.game, "Please select\n" .. (picks_needed - current_picks) .. " more!"))
                    end
                  end
                })

                local function fallback_autofill(menu)
                  if not current_match then 
                    if menu then menu:close() end 
                    return 
                  end
                  for _, item_mon in ipairs(items) do
                    if item_mon.mon then
                      if current_picks < picks_needed and not picked_mons[item_mon.mon] then
                        picked_mons[item_mon.mon] = true
                        current_picks = current_picks + 1
                        table.insert(current_match.active, item_mon.mon)
                      elseif not picked_mons[item_mon.mon] then
                        bench_mon(current_match, item_mon.mon)
                      else
                        if not is_in_table(item_mon.mon, current_match.active) then
                          table.insert(current_match.active, item_mon.mon)
                        end
                      end
                    end
                  end
                  current_match.locked = true
                  if menu then menu:close() end
                end

                local ListMenu = require("src.ui.ListMenu")
                draft_menu = ListMenu.new(self.game, "CHOOSE " .. picks_needed, items, {
                  footer = "A:SEL B:AUTOFILL",
                  onChoose = function(item)
                    if item.onSelect then item.onSelect(item) end
                  end,
                  onCancel = function(menu) fallback_autofill(menu) end
                })

                -- Stacking UI elements bottom to top.
                self.game.stack:push(draft_menu)
                self.game.stack:push(require("src.render.TextBox").new(self.game, string.format("MATCH RULES: %dV%d", enemy_count, enemy_count)))
              end
            else
              -- Top Down / Dynamic standard rules text.
              self.game.stack:push(require("src.render.TextBox").new(self.game, string.format("MATCH RULES: %dV%d", enemy_count, enemy_count)))
            end
          end
        end
        return ret
      end
    end

    -- ========================================
    -- UNIVERSAL SWITCH BLOCKER (BOTH GENS)
    -- ========================================
    -- Enforces benched limitations by wrapping Party Menu callbacks dynamically.
    if state.screenId == "PartyMenu" or state.screenId == "Gen2PartyMenu" or state.party then
      local function handle_block(orig_fn)
        return function(a, b, c, d)
          -- Safely resolve the Pokémon object dynamically across differing engine payloads.
          local mon = nil
          if type(a) == "table" and a.hp then mon = a
          elseif type(b) == "table" and b.hp then mon = b end
          
          if mon and current_match and is_benched(mon, current_match.benched) then
            local game_ref = state.game or mod.game
            require("src.core.Sound").play(game_ref.data, "Denied")
            game_ref.stack:push(require("src.render.TextBox").new(game_ref, "MATCH RULES:\nThis POKéMON is\nbenched!"))
            return true -- Silently abort the switch action.
          end
          if orig_fn then return orig_fn(a, b, c, d) end
        end
      end

      -- Gen 2 relies heavily on `onChoose`.
      if state.onChoose and not state.__fb_hooked_choose then
        state.__fb_hooked_choose = true
        state.onChoose = handle_block(state.onChoose)
      end

      -- Gen 1 and extended Gen 2 contexts rely on `onSwitch`.
      if state.onSwitch and not state.__fb_hooked_switch then
        state.__fb_hooked_switch = true
        state.onSwitch = handle_block(state.onSwitch)
      end
    end
  end)

  -- ==========================================================================
  -- REAL-TIME BATTLE EVENTS
  -- ==========================================================================

  -- Registers newly active Pokémon and enforces Dynamic limits on-the-fly.
  mod.events:on("battle.battler_switched", function(ev)
    if not current_match then return end
    
    local is_player = current_match.is_gen2 and (ev.side and ev.side.key == "player") or (ev.battler and ev.battler.isPlayer)
    if is_player then
      local new_mon = current_match.is_gen2 and ev.battler or ev.battler.mon
      if not is_in_table(new_mon, current_match.active) then
        table.insert(current_match.active, new_mon)
        local party = current_match.is_gen2 and current_match.battle.party or current_match.battle.game.save.party
        check_dynamic_limit(current_match, party)
      end
    end
  end)

  -- Actively purges "switch" interactions from the submenu context array for benched targets.
  mod.hooks:wrap("ui.party.submenu", function(next_fn, game, items, mon, ctx)
    local result = next_fn(game, items, mon, ctx)
    if ctx.battle and current_match and is_benched(mon, current_match.benched) then
      local filtered = {}
      for _, item in ipairs(result) do
        if item.action ~= "battle_switch" and item.action ~= "switch" then
          table.insert(filtered, item)
        end
      end
      return filtered
    end
    return result
  end)

  -- Handles complete wipes. Forces white-outs accurately under specific game engine constraints.
  mod.events:on("battle.fainted", function(ev)
    if not current_match then return end
    
    local is_player = current_match.is_gen2 and (ev.side and ev.side.key == "player") or (ev.battler and ev.battler.isPlayer)
    if is_player then
      local can_continue = false
      for _, mon in ipairs(current_match.active) do
        if mon.hp > 0 then
          can_continue = true
          break
        end
      end
      
      local party = current_match.is_gen2 and current_match.battle.party or current_match.battle.game.save.party
      -- Failsafe for Dynamic Mode: Validates if room permits sending out unbenched reserves.
      if not can_continue and current_match.mode == "dynamic" and #current_match.active < current_match.limit then
        for _, mon in ipairs(party) do
          if mon.hp > 0 and not is_benched(mon, current_match.benched) and not mon.isEgg then
            can_continue = true
            break
          end
        end
      end

      -- The match limits are exhausted; collapse benched HP entirely to ensure a clean wipe.
      if not can_continue then
        for _, saved in ipairs(current_match.benched) do
          saved.mon.hp = 0
        end
      end
    end
  end)

  -- Protects the visual "OUT" status from being overwritten by the game's native overlay logic.
  mod.hooks:wrap("battle.overlay", function(next_fn, battle)
    next_fn(battle)
    if current_match then
      for _, saved in ipairs(current_match.benched) do
        if saved.mon.status ~= "OUT" then
          saved.mon.status = "OUT"
        end
      end
    end
  end)

  -- ==========================================================================
  -- MATCH CLEANUP
  -- ==========================================================================
  mod.events:on("battle.ended", function(ev)
    if current_match then
      -- Fully restores the original pre-battle state of all benched Pokémon.
      for _, saved in ipairs(current_match.benched) do
        saved.mon.status = saved.status
        saved.mon.hp = saved.hp
        -- Restores the clean nickname, effectively reversing the visual UI hack.
        if saved.original_nickname then
          saved.mon.nickname = saved.original_nickname
        else
          saved.mon.nickname = nil
        end
      end
      current_match = nil
    end
  end)

end