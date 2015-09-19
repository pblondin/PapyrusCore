//
//  Player.swift
//  PapyrusCore
//
//  Created by Chris Nevin on 8/07/2015.
//  Copyright © 2015 CJNevin. All rights reserved.
//

import Foundation

public func == (lhs: Player, rhs: Player) -> Bool {
    return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
}

public enum Difficulty {
    case Human
    case Newbie
    case Average
    case Champion
}

/// An instance of a Player which has a score and can be assigned to tiles.
/// - SeeAlso: Papyrus.player is the current Player.
public final class Player: Equatable {
    public internal(set) var difficulty: Difficulty
    /// Players current score.
    public internal(set) var score: Int = 0
    /// All tiles played by this player.
    public internal(set) lazy var tiles = Set<Tile>()
    /// Current rack tiles.
    public var rackTiles: [Tile] {
        return tiles.filter({$0.placement == Placement.Rack})
    }
    /// Current play tiles, i.e. tiles on the board that haven't been submitted yet.
    public var currentPlayTiles: [Tile] {
        return tiles.filter({$0.placement == Placement.Board})
    }
    /// Currently held tile, i.e. one being dragged around.
    public var heldTile: Tile? {
        let held = tiles.filter({$0.placement == Placement.Held})
        assert(held.count < 2)
        return held.first
    }
    /// Method to return first rack tile with a given letter.
    func firstRackTile(withLetter letter: Character) -> Tile? {
        return rackTiles.filter({$0.letter == letter}).first
    }
    public init(score: Int? = 0, difficulty: Difficulty = .Human) {
        self.score = score!
        self.difficulty = difficulty
    }
    /// Submit a move, drop all tiles on the board and increment score.
    public func submit(move: Move) {
        zip(move.word.tiles, move.word.characters).forEach { (tile, character) -> () in
            if tile.value == 0 {
                tile.letter = character
            }
            assert(tile.letter == character)
        }
        zip(move.word.squares, move.word.tiles).forEach { (square, tile) -> () in
            square.tile = tile
            tile.placement = .Fixed
        }
        score += move.total
    }
}

extension Papyrus {
    /// - returns: A new player with their rack pre-filled. Or an error if refill fails.
    public func createPlayer(difficult: Difficulty = .Human) -> Player {
        let newPlayer = Player()
        replenishRack(newPlayer)
        players.append(newPlayer)
        return newPlayer
    }
    
    /// Advances to next player's turn.
    public func nextPlayer() {
        playerIndex++
        if playerIndex >= players.count {
            playerIndex = 0
        }
        lifecycleCallback?(.ChangedPlayer, self)
    }
    
    /// Draw tiles from the bag.
    /// - parameter player: Player's rack to fill.
    public func draw(player: Player) {
        // If we have no tiles left in the bag complete game
        if replenishRack(player) == 0 && player.rackTiles.count == 0 {
            // Subtract remaining tiles in racks
            for player in players {
                player.score = player.rackTiles.mapFilter({$0.value}).reduce(player.score, combine: -)
            }
            // Complete the game
            lifecycleCallback?(.Completed, self)
        }
    }
    
    /// Add tiles to a players rack from the bag.
    /// - returns: Number of tiles able to be drawn for a player.
    func replenishRack(player: Player) -> Int {
        let needed = PapyrusRackAmount - player.rackTiles.count
        var count = 0
        for i in 0..<tiles.count where tiles[i].placement == .Bag && count < needed {
            tiles[i].placement = .Rack
            player.tiles.insert(tiles[i])
            count++
        }
        return count
    }
    
    /// Move tiles from a players rack to the bag.
    public func returnTiles(tiles: [Tile], forPlayer player: Player) {
        player.tiles.subtractInPlace(tiles)
        tiles.forEach({$0.placement = .Bag})
    }
}