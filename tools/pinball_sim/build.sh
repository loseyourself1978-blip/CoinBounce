#!/bin/bash
# 把 App 里的弹球内核和 main.swift 一起用 -O 编译成 pbs
cd "$(dirname "$0")"
P=../../ios/CoinBounce
swiftc -O -o "${1:-pbs}" main.swift $P/Pinball/PinballEngine.swift $P/Pinball/PinballRules.swift $P/Pachinko/PachinkoPhysics.swift $P/Pachinko/PachinkoBoard.swift $P/Pachinko/PachinkoConstants.swift
