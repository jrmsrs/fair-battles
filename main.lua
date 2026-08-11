return function(mod)
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
        { "(Unstable) Dynamic", "dynamic" },
        { "(Unstable) Draft", "draft" }
      },
      default = "top_down"
    }
  })

  local current_match = nil

  local function is_in_table(val, tbl)
    for _, v in ipairs(tbl) do
      if v == val then return true end
    end
    return false
  end

  local function is_benched(mon, benched_tbl)
    for _, saved in ipairs(benched_tbl) do
      if saved.mon == mon then return true end
    end
    return false
  end

  local function bench_mon(match, mon)
    table.insert(match.benched, {
      mon = mon,
      status = mon.status,
      hp = mon.hp
    })
    mon.status = "OUT"
    
    -- Força HP a 1 para UI exibir pokébola escura e negar uso de Revives
    if mon.hp <= 0 then
      mon.hp = 1
    end
  end

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

  mod.events:on("battle.started", function(ev)
    current_match = nil

    if not mod.options:get("fair_battle") then return end
    if ev.kind ~= "trainer" then return end

    local battle = ev.battle
    local enemy_party = battle.enemyParty
    local player_party = battle.game.save.party

    if not enemy_party or not player_party or not battle.player then return end

    local enemy_count = #enemy_party
    local player_count = #player_party
    local mode = mod.options:get("selection_mode") or "top_down"

    current_match = {
      battle = battle,
      active = {},
      benched = {},
      limit = enemy_count,
      mode = mode,
      locked = false
    }

    local healthy_total = 0
    for _, mon in ipairs(player_party) do
      if mon.hp > 0 then healthy_total = healthy_total + 1 end
    end

    -- Queue the MATCH RULES dialogue FIRST before any UI is pushed
    if healthy_total > enemy_count then
      battle:say(string.format("MATCH RULES: %dV%d", enemy_count, enemy_count))
    end

    -- ===========================
    -- MODO 1: TOP DOWN
    -- ===========================
    if mode == "top_down" then
      local healthy_counted = 0
      for i = 1, player_count do
        local mon = player_party[i]
        if mon.hp > 0 then
          healthy_counted = healthy_counted + 1
          if healthy_counted > enemy_count then
            bench_mon(current_match, mon)
          else
            table.insert(current_match.active, mon)
          end
        else
          bench_mon(current_match, mon)
        end
      end
      current_match.locked = true
      
    -- ===========================
    -- MODO 2: DYNAMIC
    -- ===========================
    elseif mode == "dynamic" then
      local lead = battle.player.mon
      table.insert(current_match.active, lead)

      for i = 1, player_count do
        local mon = player_party[i]
        if mon.hp <= 0 and mon ~= lead then
          bench_mon(current_match, mon)
        end
      end
      
      check_dynamic_limit(current_match, player_party)

    -- ===========================
    -- MODO 3: DRAFT (BATTLE TOWER STYLE)
    -- ===========================
    elseif mode == "draft" then
      local lead = battle.player.mon
      table.insert(current_match.active, lead)

      -- Bench pre-fainted Pokémon immediately
      for i = 1, player_count do
        local mon = player_party[i]
        if mon.hp <= 0 and mon ~= lead then
          bench_mon(current_match, mon)
        end
      end

      -- If player has more healthy Pokémon than enemy count, invoke draft UI
      if healthy_total > enemy_count then
        local picks_needed = enemy_count - 1
        
        -- If enemy only has 1 Pokémon, lead is enough. Auto-bench the rest.
        if picks_needed == 0 then
          for i = 1, player_count do
            local mon = player_party[i]
            if mon ~= lead and mon.status ~= "OUT" then
              bench_mon(current_match, mon)
            end
          end
          current_match.locked = true
        else
          -- Insert Selection UI into Battle Queue
          battle:ui(function()
            local items = {}
            local current_picks = 0
            local picked_mons = {}
            
            for i = 1, player_count do
              local mon = player_party[i]
              -- Safe check: filter out lead and anyone marked OUT (which includes fainted ones)
              if mon ~= lead and mon.status ~= "OUT" then
                local item = {
                  label = mon.nickname or battle.game.data.pokemon[mon.species].name,
                  right = " ",
                  mon = mon
                }
                item.onSelect = function(self_item, menu)
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
            
            table.insert(items, {
              label = "[ FINISH ]",
              onSelect = function(self_item, menu)
                if current_picks == picks_needed then
                  -- Lock choices and close menu
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
                  menu:close()
                else
                  -- Provide UI feedback instead of just failing silently
                  require("src.core.Sound").play(battle.game.data, "Denied")
                  local TextBox = require("src.render.TextBox")
                  local missing = picks_needed - current_picks
                  battle.game.stack:push(TextBox.new(battle.game, "Please select\n" .. missing .. " more!"))
                end
              end
            })

            local function fallback_autofill()
              -- Auto-fill the missing picks to avoid exploits on B-Cancel
              for _, item_mon in ipairs(items) do
                if item_mon.mon then
                  if current_picks < picks_needed and not picked_mons[item_mon.mon] then
                    picked_mons[item_mon.mon] = true
                    current_picks = current_picks + 1
                    table.insert(current_match.active, item_mon.mon)
                  elseif not picked_mons[item_mon.mon] then
                    bench_mon(current_match, item_mon.mon)
                  else
                    table.insert(current_match.active, item_mon.mon)
                  end
                end
              end
              current_match.locked = true
            end

            return mod.ui.ListMenu.new(battle.game, "CHOOSE " .. picks_needed, items, {
              footer = "A:SEL B:AUTOFILL",
              onChoose = function(item, menu)
                if item.onSelect then item.onSelect(item, menu) end
              end,
              onCancel = function()
                fallback_autofill()
              end
            })
          end)
        end
      end
    end
  end)

  -- Continuous dynamic check for "Dynamic" mode
  mod.events:on("battle.battler_switched", function(ev)
    if current_match and ev.battler.isPlayer then
      local new_mon = ev.battler.mon
      if not is_in_table(new_mon, current_match.active) then
        table.insert(current_match.active, new_mon)
        check_dynamic_limit(current_match, current_match.battle.game.save.party)
      end
    end
  end)

  -- Prevent voluntary switching from submenu
  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local result = next(game, items, mon, ctx)
    if ctx.battle and current_match and mon.status == "OUT" then
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

  -- Prevent forced switching from items/moves via PartyMenu hook
  local orig_PartyMenu = mod.content.screens:get("PartyMenu")
  if orig_PartyMenu then
    mod.content.screens:override("PartyMenu", {
      new = function(game, opts)
        if current_match and opts and opts.battle then
          local orig_onSwitch = opts.onSwitch
          if orig_onSwitch then
            opts.onSwitch = function(mon, menu)
              if mon.status == "OUT" then
                local TextBox = require("src.render.TextBox")
                game.stack:push(TextBox.new(game, "MATCH RULES:\nThis POKéMON is\nbenched!"))
                return
              end
              return orig_onSwitch(mon, menu)
            end
          end
        end
        return orig_PartyMenu.new(game, opts)
      end
    })
  end

  -- Apply native white-out if all valid active Pokémon faint
  mod.events:on("battle.fainted", function(ev)
    if not current_match then return end
    if ev.battler.isPlayer then
      local can_continue = false
      
      for _, mon in ipairs(current_match.active) do
        if mon.hp > 0 then
          can_continue = true
          break
        end
      end
      
      -- Validate remaining options for Dynamic mode specifically
      if not can_continue and current_match.mode == "dynamic" and #current_match.active < current_match.limit then
        local party = current_match.battle.game.save.party
        for _, mon in ipairs(party) do
          if mon.hp > 0 and mon.status ~= "OUT" then
            can_continue = true
            break
          end
        end
      end

      if not can_continue then
        for _, saved in ipairs(current_match.benched) do
          saved.mon.hp = 0
        end
      end
    end
  end)

  -- Protect the "OUT" status from healing items
  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    if current_match then
      for _, saved in ipairs(current_match.benched) do
        if saved.mon.status ~= "OUT" then
          saved.mon.status = "OUT"
        end
      end
    end
  end)

  -- Restore HP and Statuses natively
  mod.events:on("battle.ended", function(ev)
    if current_match then
      for _, saved in ipairs(current_match.benched) do
        saved.mon.status = saved.status
        saved.mon.hp = saved.hp
      end
      current_match = nil
    end
  end)
end