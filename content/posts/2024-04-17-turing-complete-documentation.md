---
title: "Turing complete - self documentation"
date: 2024-04-17
tags: [gaming]
---

This is my documentation for [my own game](https://turingcomplete.game/profile/38047) of [Turing Complete](https://turingcomplete.game/).
Turing Complete purpose is to guide you through the implementation of a simple CPU, from the first logical gate to your assembly language definition.

<!--more-->

{{< callout emoji="⚠️" text="This page is mainly for myself as a reminder. This is very far from the best design and solutions, but it's the best I could do in a reasonable time :)" >}}

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
| 32      | cond_eq               |                                 | set PC to `<dest>` if `<arg1>` = `<arg2>`       |
| 33      | cond_neq              |                                 | set PC to `<dest>` if `<arg1>` != `<arg2>`      |
| 34      | cond_lt               |                                 | set PC to `<dest>` if `<arg1>` < `<arg2>`       |
| 35      | cond_le               |                                 | set PC to `<dest>` if `<arg1>` <= `<arg2>`      |
| 36      | cond_gt               |                                 | set PC to `<dest>` if `<arg1>` > `<arg2>`       |
| 37      | cond_ge               |                                 | set PC to `<dest>` if `<arg1>` >= `<arg2>`      |

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


## Solution of the level `tower of hanoi`

```
const disk_nr 0
const src 1
const dest 2
const spare 3

const R4 4
const RAM_COUNTER 5
const PROGRAM_CNTR 6
const I_0 7

const _ 0
const magnet 5

add|64 I_0 0 disk_nr
add|64 I_0 0 src
add|64 I_0 0 dest
add|64 I_0 0 spare

label hanoi
# if disk_nr == 0
cond_gt|64 disk_nr 0 else
call _ _ move
jump _ _ hanoi_end

label else

## hanoi(disk_nr - 1, source, spare, dest)
push disk_nr _ _
push src     _ _
push dest    _ _
push spare   _ _
sub|64 disk_nr 1 disk_nr
### swap spare and dest
add|64 spare 0 R4
add|64 dest 0 spare
add|64 R4 0 dest
call _ _ hanoi
pop _ _ spare
pop _ _ dest
pop _ _ src
pop _ _ disk_nr

### move disk from source to dest
call _ _ move

## hanoi(disk_nr - 1, spare, dest, source)
push disk_nr _ _
push src     _ _
push dest    _ _
push spare   _ _
sub|64 disk_nr 1 disk_nr
### swap source and spare
add|64 spare 0 R4
add|64 src   0 spare
add|64 R4   0 src
call _ _ hanoi
pop _ _ spare
pop _ _ dest
pop _ _ src
pop _ _ disk_nr

label hanoi_end
ret


label move
add|64     src    0 I_0 # move to spot src
add|64|128 magnet 0 I_0 # toggle magnet
add|64 	   dest   0 I_0 # move to spot dest
add|64|128 magnet 0 I_0 # toggle magnet
ret
```

## Solution of the level `water world`

```
const R0 0
const leftwall 0

const R1 1
const rightwall 1

const R2 2

const R3 3
const IDX 3

const R4 4
const volume 4

const R5 5
const RAM_PNTR 5

const PROGRAM_CNTR 6
const I_O 7
const arraysize 15
const _ 0

# Load in memory
label copy_mem
ram_input I_O _ _
add|64 RAM_PNTR 1 RAM_PNTR
cond_le|64 RAM_PNTR arraysize copy_mem

# Init Registers
add|64|128 0 0 RAM_PNTR
add|64   IDX 1 IDX

label main_loop
call _ _ find_left_wall
call _ _ find_right_wall

# R2=min(left,right)
cond_lt leftwall rightwall left_is_smaller
cond_gt leftwall rightwall right_is_smaller
jump _ _ left_right_equal

label left_is_smaller
add|64 leftwall 0 R2
jump _ _ add_vol

label right_is_smaller
add|64 rightwall 0 R2
jump _ _ add_vol

label left_right_equal
add|64 rightwall 0 R2
jump _ _ add_vol

# Add to total volume
label add_vol
add|64 IDX 0 RAM_PNTR
ram_output _ _ R1
sub R2 R1 R2
add R2 volume volume

add|64 IDX 1 IDX
cond_lt|64 IDX arraysize main_loop

add|64 volume 0 I_O

label find_left_wall
push R2  _ _
push IDX _ _

add|64 IDX 0 RAM_PNTR
ram_output _ _ leftwall

label find_left_wall_loop
sub|64 IDX 1 IDX
add|64 IDX 0 RAM_PNTR
ram_output _ _ R2
cond_gt leftwall R2 find_left_wall_loop_continue
add|64 R2 0 leftwall
label find_left_wall_loop_continue
cond_eq|64 IDX 0 find_left_wall_end
jump _ _ find_left_wall_loop
label find_left_wall_end

pop _ _ IDX
pop _ _ R2
ret


label find_right_wall
push R2  _ _
push IDX _ _

add|64 IDX 0 RAM_PNTR
ram_output _ _ rightwall

label find_right_wall_loop
add|64 IDX 1 IDX
add|64 IDX 0 RAM_PNTR
ram_output _ _ R2
cond_gt rightwall R2 find_right_wall_loop_continue
add|64 R2 0 rightwall
label find_right_wall_loop_continue
cond_eq|64 IDX arraysize find_right_wall_end
jump _ _ find_right_wall_loop
label find_right_wall_end

pop _ _ IDX
pop _ _ R2

ret
```
