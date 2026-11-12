#!/bin/bash
# 把 App 里的弹子机内核和 main.swift 一起用 -O 编译成 pks
cd "$(dirname "$0")"
P=../../../ios/CoinBounce/Pachinko
swiftc -O -o "${1:-pks}" main.swift $P/PachinkoConstants.swift $P/PachinkoBoard.swift $P/PachinkoPhysics.swift $P/PachinkoModel.swift $P/PachinkoSimulator.swift
