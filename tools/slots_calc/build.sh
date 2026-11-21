#!/bin/bash
cd "$(dirname "$0")"
P=../../ios/CoinBounce
swiftc -O -o slc main.swift $P/Slots/SlotsMath.swift $P/Slots/CaishenMath.swift $P/Pachinko/PachinkoPhysics.swift $P/Pachinko/PachinkoBoard.swift $P/Pachinko/PachinkoConstants.swift
