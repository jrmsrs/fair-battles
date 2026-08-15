# gen1recomp - Fair Battles Mod (Red, Blue, Yellow, Gold)

a QoL and somewhat of a dynamic scaling mod that limits your usable party size to match the number of PKM your opponent has.

![thumbnail](./7edd7385-145c-497e-a132-b303900968a2.jpg)

while some difficulty mods/rom hacks try to make battles fairer by just increasing the number of PKM every opponent has, this mod takes the opposite approach to preserve the vanilla pacing. 
there's a reason early route trainers only pack 2 or 3 PKM—early game battles are naturally tedious when your entire moveset consists of just Tackle, Growl, and Water Gun —,
you really shouldn't have to waste time slogging through a Bug Catcher with 6 Metapods just to feel some baseline level of risk during your playthrough.

if you have 6 PKM and challenge a Youngster with 2, you will only be allowed to use 2 healthy PKM in your party. 
if all of your active PKM faint, you will white-out, regardless of the healthy PKM sitting in the back.

## Features

* **compatible with Gen 1 and Gen 2:** this mod works with both the original Red/Blue/Yellow games and the current beta Pokémon Gold.
* **dynamic party limiting:** automatically matches your usable party size to the opponent's party size during trainer battles.
* **customizable selection modes:** head to the game's Mod Options to choose how you want your active team to be selected:
  * **Top Down (Default):** the mod automatically counts your healthy PKM from the top of your party down, putting the rest on the "bench" for the duration of the match.
  * **Dynamic:** your bench remains unlocked at the start. any PKM you send out becomes part of your active roster. once your active roster reaches the opponent's limit, the remaining unsent PKM are benched.
  * **Draft:** battle tower style! a UI menu pops up before the battle begins, letting you manually pick your active roster for that specific match.
* **benched status:** disabled PKM are given a temporary "OUT" status. they appear as dark Poké Balls in the UI and naturally cannot be revived or healed during the match. once the battle concludes, your benched PKM are seamlessly restored to their exact pre-battle HP and status conditions.
* **wild battles unaffected:** restrictions only apply to trainer battles, allowing you to use your full party for wild encounters and catching.

## Recommended Synergies

this mod was designed to fit seamlessly with other difficulty and immersion mods. for the best experience, i highly recommend playing it alongside:

* **[Dynamic Scaling](https://github.com/FelizNavidad-D/Gen1-Recomp-Mods/releases):** for those who want a more challenging experience, the original inspiration for this mod. pairing them together creates the perfect middle ground: the game stays consistently challenging, but battles remain quick and keep that vanilla-ish pacing without turning every random encounter into an extreme 6v6 gauntlet.
* **[Trainers Let You Choose Lead Pokemon](https://github.com/ZyranCZ/Trainers-Let-You-Choose-Lead-Pokemon):** for the ultimate "anime battle" vibe. your opponent reveals their first Pokémon, you manually select your counter-lead, and then the fair battle limits apply perfectly to the rest of the match.

## Installation

Place the `fair_battles` folder directly into your `mods/` directory and ensure it is enabled in the game's Mod Manager.