return function(mod)
  mod.options:define({
    {
      key = "fair_battle",
      type = "toggle",
      label = "FAIR BATTLE",
      default = true
    }
  })

  local current_match = nil

  mod.events:on("battle.started", function(ev)
    current_match = nil

    if not mod.options:get("fair_battle") then return end
    if ev.kind ~= "trainer" then return end

    local battle = ev.battle
    local enemy_party = battle.enemyParty
    local player_party = battle.game.save.party

    if not enemy_party or not player_party then return end

    local enemy_count = #enemy_party
    local player_count = #player_party

    local active = {}
    local benched = {}

    local healthy_counted = 0
    for i = 1, player_count do
      local mon = player_party[i]
      if mon.hp > 0 then
        healthy_counted = healthy_counted + 1
        if healthy_counted > enemy_count then
          table.insert(benched, mon)
        else
          table.insert(active, mon)
        end
      else
        -- Pokemon that are already fainted also get benched
        table.insert(benched, mon)
      end
    end

    if #benched > 0 then
      current_match = {
        battle = battle,
        active = active,
        benched = {}
      }

      battle:say(string.format("MATCH RULES: %dV%d", enemy_count, enemy_count))

      for _, mon in ipairs(benched) do
        -- Save original stats, including the 0 HP of fainted mons
        table.insert(current_match.benched, {
          mon = mon,
          status = mon.status,
          hp = mon.hp
        })
        mon.status = "OUT"
        
        -- Temporarily give fainted Pokemon 1 HP. 
        -- This forces the dark status pokeball in the UI instead of the fainted ball, 
        -- and naturally prevents the player from using a Revive (which requires HP == 0).
        if mon.hp <= 0 then
          mon.hp = 1
        end
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
      local all_fainted = true
      for _, mon in ipairs(current_match.active) do
        if mon.hp > 0 then
          all_fainted = false
          break
        end
      end

      if all_fainted then
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