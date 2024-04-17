---
title: "Turing complete - self documentation"
date: 2024-04-17
---

This is my documentation for [my own game](https://turingcomplete.game/profile/38047) of [Turing Complete](https://turingcomplete.game/).
Turing Complete purpose is to guide you through the implementation of a simple CPU, from the first logical gate to your assembly language definition.

This page is mostly intended to myself as a reminder.
This is very far from the best design and solutions, but it's the best I could do in a reasonable time :)

<!--more-->

## Schematic

[![My own computer in Turing Complete](turing_complete_annotated.png)](turing_complete_annotated.png)

[Raw version, non annnotated](turing_complete.png)

## Instructions set

### Syntax

Instruction `<op code> <arg1> <arg2> <dest>`

`<arg1>` and `<arg2>` can be set to an immediate value with bitwise OR on the opcode:

* for `arg1`, `<op code>|128`
* for `arg2`, `<op code>|64`

### Table

| OP Code | Assembly instruction  | Parameters                      | Comment                                         |
|---------|-----------------------|---------------------------------|-------------------------------------------------|
| 0       | add                   |                                 | `<arg1>` + `<arg2>` in register `<dest>`        |
| 1       | sub                   |                                 | `<arg1>` - `<arg2>` in register `<dest>`        |
| 2       | and                   |                                 | `<arg1>` AND `<arg2>` in register `<dest>`      |
| 3       | or                    |                                 | `<arg1>` OR `<arg2>` in register `<dest>`       |
| 4       | not                   |                                 | `<arg1>` NOT `<arg2>` in register `<dest>`      |
| 5       | xor                   |                                 | `<arg1>` XOR `<arg2>` in register `<dest>`      |
| 6       | shift_right           |                                 | shift right `<arg1>` by `<arg2>` in register `<dest>`  |
| 7       | shift_left            |                                 | shift left `<arg1>` by `<arg2>` in register `<dest>`  |
| 8       | ram_input             | `<src> <unused> <unused>`       | Store `<arg1>` in RAM at the address stored in R5 |
| 9       | ram_output            | `<unused> <unused> <dest>`      | Copy to `<dest>` the value stored at the RAM address stored in R5 |
| 10      | mul                   |                                 | `<arg1>` * `<arg2>` in register `<dest>`        |
| 11      | push                  | `<src> <unused> <unused>`       | Push `<arg1>` to the stack                      |
| 12      | pop                   | `<unused> <unused> <dest>`      | Pop the stack into `<dest>`                     |
| 13      | call                  | `<unused> <unused> <dest>`      | push PC+4 to the stack and set the PC to `dest` |
| 14      | ret                   | `<unused> <unused> <unused>`    | pop the stack to the PC                         |
| 32      | eq                    |                                 | set PC to `<dest>` if `<arg1>` = `<arg2>`       |
| 33      | neq                   |                                 | set PC to `<dest>` if `<arg1>` != `<arg2>`      |
| 34      | lt                    |                                 | set PC to `<dest>` if `<arg1>` < `<arg2>`       |
| 35      | le                    |                                 | set PC to `<dest>` if `<arg1>` <= `<arg2>`      |
| 36      | gt                    |                                 | set PC to `<dest>` if `<arg1>` > `<arg2>`       |
| 37      | ge                    |                                 | set PC to `<dest>` if `<arg1>` >= `<arg2>`      |

## Addresses

| Register address | Register name            |
|------------------|--------------------------|
| 0                | Register 0               |
| 1                | Register 1               |
| 2                | Register 2               |
| 3                | Register 3               |
| 4                | Register 4               |
| 5                | Register 5 - ram pointer |
| 6                | Program Counter (PC)     |
| 7                | Input/Output             |

## Solution of the level `unseen fruit`

```
# Constants definitions for readability
const R0 0
const R1 1
const R2 2
const R3 3
const R4 4

const RAM_PNTR 5
const PROGRAM_CNTR 6
const I_O 7

const _ 0 #UNUSED PARAM

const COUNTER 1

# Go to conveyor belt
add|64|128 2 0 I_O
add|64|128 1 0 I_O
add|64|128 2 0 I_O
add|64|128 1 0 I_O
add|64|128 1 0 I_O
add|64|128 1 0 I_O
add|64|128 1 0 I_O
add|64|128 2 0 I_O
add|64|128 1 0 I_O
add|64|128 0 0 I_O
add|64|128 1 0 I_O


label main_loop_begin
# copy input in R0
add|64|128 3 0 I_O
add|64 I_O 0 R0
# if input = 92, wait for a fruit
cond_eq|64 R0 92 main_loop_begin
# if input != 92, call function check
call _ _ check
jump _ _ main_loop_begin
label main_loop_end

jump _ _ end

# function check - # check if fruit has already been seen
label check
add|64|128 0 0 RAM_PNTR
label check_loop_begin
# load ram
ram_output _ _ R2
add|128 1 RAM_PNTR RAM_PNTR
cond_eq R0 R2 check_push
cond_gt RAM_PNTR COUNTER check_store
jump _ _ check_loop_begin

# function check_store
# if input number is not in memory, store the number
label check_store
call _ _ store
jump _ _ check_loop_end

# function check_push
# else, push the button
label check_push
call _ _ push
jump _ _ check_loop_end
label check_loop_end
cond_le R2 COUNTER check_loop_begin
label check_end
ret

# function store
# Append a new value in RAM
label store
add|128 1 COUNTER COUNTER
add|128 0 COUNTER RAM_PNTR
ram_input R0 _ _
ret

# Push the button
label push
add|64|128 2 0 I_O
add|64|128 4 0 I_O
add|64|128 0 0 I_O
ret

label end
```

## Solution of the level `delicious order`


The program works in 3 steps:

1. loads all the values from I_O and store them in memory
2. performs a bubble sort, suboptimal - O(n²) - but easy and readable
3. Output the sorted data

```
const R0 0
const R1 1
const R2 2
const R3 3
const R4 4

const RAM_PNTR 5
const PROGRAM_CNTR 6
const I_O 7

const _ 0

const array_size 15

# Init Registers to 0
add|64|128 0 0 R0
add|64|128 0 0 R1
add|64|128 0 0 R2
add|64|128 0 0 R3
add|64|128 0 0 R4
add|64|128 0 0 RAM_PNTR

# Load in memory
label load
push I_O _ _
add|64 RAM_PNTR 1 RAM_PNTR
cond_le|64 RAM_PNTR array_size load
add|64|128 _ _ RAM_PNTR # set to 0
label copy_mem
pop _ _ R0
ram_input R0 _ _
add|64 RAM_PNTR 1 RAM_PNTR
cond_le|64 RAM_PNTR array_size copy_mem

# Init Registers to 0
add|64|128 0 0 R0
add|64|128 0 0 RAM_PNTR

const I R0
const MAX_I array_size
const J R1
const MAX_J R2

label main_loop

sub|128 MAX_I I MAX_J

label inner_loop

# Compare and swap
# RAM_PNTR <- J
add J 0 RAM_PNTR
# R3 <- RAM
ram_output  _ _ R3
# RAM_PNTR <- J+1
add|64 RAM_PNTR 1 RAM_PNTR
# R4 <- RAM
ram_output  _ _ R4
# if R3 > R4, Swap R3-R4
cond_le R3 R4 no_swap
#  Push R3 to RAM_PNTR[J+1]
ram_input R3 _ _
#  Push R4 to RAM_PNTR[J]
sub|64 RAM_PNTR 1 RAM_PNTR
ram_input R4 _ _
label no_swap

# end inner_loop

add|64 J 1 J
cond_lt J MAX_J inner_loop
add|64|128 0 0 J

# end main_loop
add|64 I 1 I
cond_lt|64 I MAX_I main_loop



# Unload
add|64|128 0 0 RAM_PNTR
label unload
add|64 RAM_PNTR 1 RAM_PNTR
ram_output _ _ I_O
cond_le|64 RAM_PNTR array_size unload
```

