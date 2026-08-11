return function(mod)
  mod.options:define({
    {
      key = "fair_battle",
      type = "toggle",
      label = "FAIR BATTLE",
      default = true
    }
  })

  local disabled_pokemon = {}

  mod.events:on("battle.started", function(ev)
    disabled_pokemon = {}

    if not mod.options:get("fair_battle") then return end
    if ev.kind ~= "trainer" then return end

    local battle = ev.battle
    local enemy_party = battle.enemyParty
    local player_party = battle.game.save.party

    if not enemy_party or not player_party then return end

    local enemy_count = #enemy_party
    local player_count = #player_party

    local healthy_counted = 0
    local to_disable = {}

    for i = 1, player_count do
      local mon = player_party[i]
      if mon.hp > 0 then
        healthy_counted = healthy_counted + 1
        if healthy_counted > enemy_count then
          table.insert(to_disable, mon)
        end
      end
    end

    if #to_disable > 0 then
      battle:say(string.format("MATCH RULES: %dV%d", enemy_count, enemy_count))

      for _, mon in ipairs(to_disable) do
        table.insert(disabled_pokemon, {
          mon = mon,
          hp = mon.hp,
          status = mon.status
        })
        mon.hp = 0
        mon.status = "FNT"
      end
    end
  end)

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    
    for _, saved in ipairs(disabled_pokemon) do
      if saved.mon.hp > 0 then
        saved.hp = saved.hp + saved.mon.hp
        saved.mon.hp = 0
        saved.mon.status = "FNT"
      end
    end
  end)

  mod.events:on("battle.ended", function(ev)
    for _, saved in ipairs(disabled_pokemon) do
      saved.mon.hp = saved.hp
      saved.mon.status = saved.status
    end
    disabled_pokemon = {}
  end)
end