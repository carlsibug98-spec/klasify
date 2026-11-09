# City College — IT Building campus data

Source: the building's emergency evacuation plan signage (four photos supplied
2026-11-09; sheet numbers 4/20, 13/20, 19/20 plus the unnumbered second-floor
sheet). Each sheet is drawn from one room, so "you are here" moves; the room
list and exit letters below are the common layout.

The plans are linear corridor layouts — one long corridor with rooms on one
side — which is good news for the app: a horizontal floor strip is enough for
the mini map, and a room directory needs only floor + position + nearest exit.

## Floors and rooms

### First (Ground) Floor — Room 102 (sheet 4/20)

Left → right along the corridor:

| Order | Room / area | Notes |
|---|---|---|
| 1 | Toilet + Stairs (left end) | **Exit A — left-end ramp** |
| 2 | Board Room | |
| 3 | IE Office | |
| 4 | Admin Office | |
| 5 | Faculty Office | |
| 6 | Dean | |
| 7 | Consultation | |
| 8 | Clinic | |
| 9 | Room 102 | plan is drawn from here |
| 10 | Room 101 | |
| 11 | Toilet + Stairs (right end) | **Exit C — right-end ramp** |

- **Exit B** — front stairs beside the elevator (center-left, below the corridor).
- **Elevator** — center-left; marked **do not use** during an emergency.
- Primary route from Room 102: left door → Exit B. Alternate: right door →
  Exit C.

### Second Floor — Network Lab

| Order | Room / area | Notes |
|---|---|---|
| 1 | Toilet + Stairs (left end) | **Exit A — left-end stairs** |
| 2 | Storage | |
| 3 | Office | small office under Storage |
| 4 | Mac Lab | |
| 5 | Network Lab | plan is drawn from here |
| 6 | Computer Lab 2 | |
| 7 | Computer Lab 1 | |
| 8 | Toilet + Stairs (right end) | **Exit B — right-end stairs** |

- **Elevator** — corridor center; marked **do not use**.
- Primary route from Network Lab: left door → Exit A. Alternate: right door →
  Exit B (about the same distance).

### Third Floor — Computer Lab 4 (sheet 13/20)

The corridor runs along the left side; rooms sit in a column:

| Order | Room / area | Notes |
|---|---|---|
| 1 | Toilet + Stairs (top end) | **Exit A — left-end stairs** |
| 2 | Computer Lab 6 | |
| 3 | Computer Lab 5 | |
| 4 | Computer Lab 4 | plan is drawn from here |
| 5 | Computer Lab 3 | |
| 6 | Room 301 | |
| 7 | Toilet + Stairs (bottom end) | **Exit B — right-end stairs** |

- **Elevator** — beside the Lab 4 / Lab 5 boundary; marked **do not use**.
- Primary route from Computer Lab 4: Exit A. Alternate: Exit B.

### Fourth Floor — Room 402 (sheet 19/20)

| Order | Room / area | Notes |
|---|---|---|
| 1 | Toilet + Stairs (left end) | **Exit A — left-end stairs** |
| 2 | Room 405 | |
| 3 | Room 404 | |
| 4 | Room 403 | |
| 5 | Room 402 | plan is drawn from here |
| 6 | Room 401 | |
| 7 | Toilet + Stairs (right end) | **Exit B — right-end stairs** |

- **Elevator** — corridor center; marked **do not use**.
- Primary route from Room 402: right door → Exit B (right-end stairs) and down.
  Alternate: left along the corridor → Exit A.

## Exit index

| Exit | First (Ground) Floor | Floors 2–4 |
|---|---|---|
| A | Left-end ramp | Left-end stairs (go down) |
| B | Front stairs beside the elevator | Right-end stairs (go down) |
| C | Right-end ramp | — |

## Gaps to fill before the directory is complete

- **First floor**: confirmed — the Ground Floor is the first floor.
- **Remaining sheets**: the 20 sheets are room-specific copies of the same
  floor layouts (each has its own "you are here" dot). The four photos already
  show the full corridor room list for floors 1–4, so the other sheets are
  only needed if they reveal a room/area not listed above. No rush.
- **Room numbers** for the labs and offices (only Computer Lab 1–6, Room 301
  and Rooms 401–405 are named/known).
- **Building entrance** (which end/level students enter from) and the campus
  path to it.
- **Accessibility**: upper floors are stairs-only in these plans; the ground
  floor has ramps at both ends. Confirm whether that is the intended accessible
  route.

## Directory model this implies

```
building: IT Building
floor:    1 (ground) | 2 | 3 | 4
wing:     left | center | right
room:     name + optional number + aliases
exits:    primary + alternate, with kind (stairs / ramp / front stairs)
```

Search should accept "lab 4", "computer lab 4", "room 402", "clinic", "dean",
"network lab" and similar aliases, and return: floor, wing, primary exit,
alternate exit.
