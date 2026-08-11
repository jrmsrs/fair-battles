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
        { "Dynamic", "dynamic" }
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
    
    -- Spoof HP to 1 so the engine draws the dark UI ball and natively rejects Revives.
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
      
    elseif mode == "dynamic" then
      local lead = battle.player.mon
      table.insert(current_match.active, lead)

      for i = 1, player_count do
        local mon = player_party[i]
        -- Even in dynamic mode, pre-fainted mons cannot be chosen
        if mon.hp <= 0 and mon ~= lead then
          bench_mon(current_match, mon)
        end
      end
      
      check_dynamic_limit(current_match, player_party)
    end

    if healthy_total > enemy_count then
      battle:say(string.format("MATCH RULES: %dV%d", enemy_count, enemy_count))
    end
  end)

  -- Track dynamically sent out Pokémon
  mod.events:on("battle.battler_switched", function(ev)
    if current_match and ev.battler.isPlayer then
      local new_mon = ev.battler.mon
      if not is_in_table(new_mon, current_match.active) then
        table.insert(current_match.active, new_mon)
        check_dynamic_limit(current_match, current_match.battle.game.save.party)
      end
    end
  end)

  -- Prevent voluntary switching from the submenu
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

  -- Prevent forced switching by intercepting PartyMenu's onSwitch
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

  -- If all allowed active Pokemon faint, drop benched HP to 0 to trigger white-out
  mod.events:on("battle.fainted", function(ev)
    if not current_match then return end
    if ev.battler.isPlayer then
      local can_continue = false
      
      -- Check if any already-active Pokémon is still alive
      for _, mon in ipairs(current_match.active) do
        if mon.hp > 0 then
          can_continue = true
          break
        end
      end
      
      -- Check if there are valid unbenched options left (Dynamic Mode)
      if not can_continue and #current_match.active < current_match.limit then
        local party = current_match.battle.game.save.party
        for _, mon in ipairs(party) do
          if mon.hp > 0 and mon.status ~= "OUT" then
            can_continue = true
            break
          end
        end
      end

      -- If the player cannot continue the match, trigger a native white-out
      if not can_continue then
        for _, saved in ipairs(current_match.benched) do
          saved.mon.hp = 0
        end
      end
    end
  end)

  -- Ensure items like Full Heal do not clear the OUT status
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

  -- Seamlessly restore all original HP and statuses after the match
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