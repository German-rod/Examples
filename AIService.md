# AI Service

Developed a scalable enemy AI framework in Roblox Luau for a wave survival game. It supports 30–50 concurrent agents, uses flowfield pathfinding for movement, and includes an engagement token system that distributes attackers across players.

[Demonstration](https://youtu.be/vDKeDJfWHKc)
---

## Architecture Overview

```
AIService
├── Registries
│   └── AgentRegistry          
├── Perception
│   └── PerceptionService      
├── Pathfinding
│   └── FlowfieldManager       # one flowfield per player target, sampled by all agents chasing them
├── Classes
│   └── Agent                  # owns all controllers + state machine, single Update/Think entry point
├── Controllers
│   ├── PerceptionController   # reads from PerceptionService, caches nearest player per agent
│   ├── MovementController     
│   ├── CombatController       
│   └── SeparationController   
├── StateMachine               # holds one active state, handles Enter/Update/Exit transitions
├── States
│   ├── RoamingState           # wanders randomly, scans for players
│   ├── ChasingState           # paths toward nearest player via flowfield
│   ├── AttackingState         # holds engagement token, executes attacks
│   └── CirclingState          # no token available, orbits player at attack range waiting for slot
├── Behaviors
│   ├── Archetypes
│   │   ├── BrawlerArchetype   # closes distance aggressively
│   │   └── StalkerArchetype   # maintains preferred range, repositions if too far
│   └── Attacks
│       ├── AttackBase         # IsReady(), Consume(), Execute() interface
│       ├── Swipe              
│       └── Projectile
└── Enemies
    ├── Mutant                 # Brawler — swipe
    └── Vanguard               # Stalker — projectile
```
<img width="7596" height="5430" alt="AI Agent State Management-2026-07-17-102643" src="https://github.com/user-attachments/assets/d08ca885-1ce2-41eb-80a0-c13c38c67cb1" />
---

## Key Systems

### Flowfield Pathfinding

Rather than computing a unique path per agent using Roblox's `PathfindingService`, this system generates one shared flowfield per player target using [FastFlow](https://devforum.roblox.com/t/fastflow-fast-flowfield-generation-for-performant-swarm-pathfinding/3280348). 

**The Problem:** Traditional A* pathfinding scales at **O(A)** where cost is tied directly to the number of agents ($A$).

**The Solution:** All agents chasing the same target sample directions from the exact same pre-calculated grid. This scales at **O(P)** where cost is tied strictly to active player targets ($P$).

```
50 agents chasing player A → 1 flowfield, 50 direction lookups
Traditional pathfinding    → 50 PathfindingService:ComputeAsync() calls
```

### Finite State Machine

Each agent owns a `StateMachine` that holds exactly one active state at a time. States are objects implementing an `Enter / Update / Exit` lifecycle.

```
Roaming → (player detected) → Chasing → (in range + token) → Attacking
                                       → (no token)         → Circling
Attacking / Circling → (player lost) → Roaming
```

---

### Engagement Token System

`AIService` maintains a token pool per player. An agent must hold a token to enter `AttackingState`. Agents without a token enter `CirclingState` and retry on an interval.

### Behavioral Archetypes

Archetypes are strategy objects that define how an agent positions itself relative to its target. Each archetype implements three methods:

- `Navigate()`: commands the movement
- `IsPositioned()`: whether the agent is already in a good spot

- `GetDesiredPosition()`: returns the desired position for the archetype.

`ChasingState` and `AttackingState` contain no archetype-specific logic. Instead, they delegate positioning decisions to the assigned archetype, keeping the state machine independent of individual enemy behaviors.
| Archetype | Behavior |
|-----------|----------|
| Brawler | Closes distance directly, uses flowfield toward target |
| Stalker | Navigates to preferred range, holds position once there, commits if player closes in |

Adding a new archetype (Flanker, Supporter, etc.) requires no changes to any state.

---

### Data-Driven Enemy Definitions

Enemy types are pure data modules. A new enemy requires zero new code, just a new file referencing existing behavior classes with different numbers:

```lua
-- Mutant
local BrawlerArchetype = require(.../Archetypes/BrawlerArchetype)
local Swipe            = require(.../Attacks/Swipe)
local JumpAttack       = require(.../Attacks/JumpAttack)

return {
    Name                 = 'Mutant',
    DetectionRange       = 100,
    AttackRange          = 40,
    AttackGlobalCooldown = 2,
    WalkSpeed            = 12,
    Archetype            = BrawlerArchetype.new({ PreferredRange = 5 }),
    Attacks = {
        { Class = Swipe,      Data = { Damage = 30, Range = 8,  Cooldown = 1.5, IdealRange = { Min = 0,  Max = 8  } } },
    }
}
```

---

### Performance
Because agent movement simply reads from an $O(1)$ directional lookup table, the pathfinding logic scales constantly regardless of swarm size. However, because agents are still fully simulated Roblox Humanoids, engine-level tasks like physics, collisions, and rig rendering remain the primary bottlenecks for massive swarms.

**Batched think & per-frame update**, agent state decisions (`Think`) are separated from physics (`Update`). Movement and perception run every frame; state machine logic is batched across frames and throttled by distance to the nearest player.

```lua
-- Agents far from any player think at ~6Hz
-- Agents within detection range think every frame
local thinkInterval = nearestDist < self.Data.DetectionRange and 0 or 0.15
```

**Centralized perception**: `PerceptionService` runs one player position scan per frame. All `PerceptionController` instances read from this cached result rather than each scanning independently. With 50 agents and 4 players this reduces distance checks from 200/frame to 4/frame for the scan itself.

**Perfomance with a Single player and 30-50 Agents**: Script server % usage stays relatively low at around 2%-4%.

---

## What I'd Do Differently

**Not using roblox humanoids**: This prototype relies on Roblox Humanoids for movement and animation. At large swarm sizes, the engine overhead of simulating Humanoids, physics, and collisions becomes the dominant performance cost. A more scalable approach would replace Humanoids with a data-oriented server simulation backed by a custom replication service.

---

## Built With

- **Luau**
- **[FastFlow]((https://devforum.roblox.com/t/fastflow-fast-flowfield-generation-for-performant-swarm-pathfinding/3280348))**: flowfield generation module by [bob_factory](https://devforum.roblox.com/t/fastflow-fast-flowfield-generation-for-performant-swarm-pathfinding/3280348)
