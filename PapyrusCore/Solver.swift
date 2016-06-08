//
//  Solver.swift
//  PapyrusCore
//
//  Created by Chris Nevin on 24/04/2016.
//  Copyright © 2016 CJNevin. All rights reserved.
//

import Foundation

typealias WordPosition = (x: Int, y: Int)

protocol WordRepresentation {
    var word: String { get }
    var x: Int { get }
    var y: Int { get }
    var horizontal: Bool { get }
    
    func length() -> Int
    func toPositions() -> [WordPosition]
    func position(forIndex index: Int) -> WordPosition
}

extension WordRepresentation {
    func length() -> Int {
        return word.characters.count
    }
    
    func toPositions() -> [WordPosition] {
        return (0..<word.characters.count).flatMap{ position(forIndex: $0) }
    }
    
    func position(forIndex index: Int) -> WordPosition {
        return (x + (horizontal ? index : 0),
                y + (horizontal ? 0 : index))
    }
}

public struct Word: WordRepresentation {
    let word: String
    let x: Int
    let y: Int
    let horizontal: Bool
}

public struct Solution: WordRepresentation {
    public let word: String
    public let x: Int
    public let y: Int
    public let horizontal: Bool
    public let score: Int
    let intersections: [Word]
    let blanks: [(x: Int, y: Int)]
    
    init(word: String, x: Int, y: Int, horizontal: Bool, score: Int, intersections: [Word], blanks: [(x: Int, y: Int)]) {
        self.word = word
        self.x = x
        self.y = y
        self.horizontal = horizontal
        
        self.intersections = intersections
        self.score = score
        self.blanks = blanks
    }
    
    init(word: Word, score: Int, intersections: [Word], blanks: [(x: Int, y: Int)]) {
        self.word = word.word
        self.x = word.x
        self.y = word.y
        self.horizontal = word.horizontal
        
        self.intersections = intersections
        self.score = score
        self.blanks = blanks
    }
    
    public func getPositions() -> [(x: Int, y: Int)] {
        var points = toPositions()
        intersections.map({ $0.toPositions() }).forEach({ intersectedPoints in
            intersectedPoints.forEach({ intersectedPoint in
                if !points.contains({ $0.x == intersectedPoint.x && $0.y == intersectedPoint.y }) {
                    points.append(intersectedPoint)
                }
            })
        })
        return points
    }
}

public enum ValidationResponse {
    case InvalidArrangement
    case InvalidWord(x: Int, y: Int, word: String)
    case Valid(solution: Solution)
    
    static func invalid(withWord word: Word) -> ValidationResponse {
        return .InvalidWord(x: word.x, y: word.y, word: word.word)
    }
}

struct Solver {
    private(set) var board: Board
    private(set) var boardState: BoardState
    private(set) var distribution: LetterDistribution
    let lookup: Lookup
    private let debug: Bool
    private let maximumWordLength = 15
    private let allTilesUsedBonus = 50
    private let operationQueue = NSOperationQueue()
    
    init(board: Board, lookup: Lookup, distribution: LetterDistribution, debug: Bool = false) {
        self.board = board
        self.distribution = distribution
        boardState = BoardState(board: board)
        self.debug = debug
        self.lookup = lookup
    }
    
    private func charactersAt(x: Int, y: Int, length: Int, horizontal: Bool) -> [Int: Character]? {
        let size = board.config.size
        var fixedLetters = [Int: Character]()
        var index = 0
        var offset = boardState[horizontal, y, x]
       
        func addCharacter(mustExist: Bool, alwaysIncrement: Bool) -> Bool {
            if offset >= size { return false }
            var didExist = false
            if let value = board[horizontal ? offset : x, horizontal ? y : offset] {
                fixedLetters[index] = value
                didExist = true
            }
            // Only increment if alwaysIncrement is set or we found a value.
            if alwaysIncrement || didExist {
                index += 1
                offset += 1
            }
            return mustExist == true ? didExist : true
        }

        while addCharacter(true, alwaysIncrement: false) { }
        for _ in 0..<length { addCharacter(false, alwaysIncrement: true) }
        while addCharacter(true, alwaysIncrement: false) { }
        
        return length != index ? nil : fixedLetters
    }
    
    private func wordAt(x: Int, y: Int, points: [(x: Int, y: Int, letter: Character)], horizontal: Bool) -> (word: Word, valid: Bool)? {
        if horizontal && x > 0 && board.isFilledAt(x - 1, y) {
            return wordAt(x - 1, y: y, points: points, horizontal: horizontal)
        } else if !horizontal && y > 0 && board.isFilledAt(x, y - 1) {
            return wordAt(x, y: y - 1, points: points, horizontal: horizontal)
        }
        
        let size = board.config.size
        let start: Int = boardState[horizontal, y, x]
        var offset: Int = start
        var characters = [Character]()
        
        while offset < size {
            let _x = horizontal ? offset : x
            let _y = horizontal ? y : offset
            guard let letter = board[_x, _y] ?? points.filter({ $0.x == _x && $0.y == _y}).first?.letter else {
                break
            }
            characters.append(letter)
            offset += 1
        }
        
        if characters.count < 2 {
            return nil
        }
        
        let word = Word(word: String(characters),
                        x: horizontal ? start : x,
                        y: horizontal ? y : start,
                        horizontal: horizontal)
        return (word, lookup.dictionary.lookup(word.word))
    }
    
    private func calculateScore(word: WordRepresentation, intersectedWords: [Word], blanks: [(x: Int, y: Int)]) -> Int {
        var tilesUsed = 0
        var score = 0
        var scoreMultiplier = 1
        var intersectionsScore = 0
        
        func isBlankAt(x: Int, y: Int) -> Bool {
            return blanks.contains({ $0.x == x && $0.y == y})
        }
        
        func letterPoints(letter: Character, atX x: Int, y: Int) -> Int {
            return isBlankAt(x, y: y) ? 0 : distribution.letterPoints[letter]!
        }
        
        func scoreWord(word: Word) -> Int {
            let chars = Array(word.word.characters)
            return word.toPositions().enumerate()
                .flatMap({ letterPoints(chars[$0], atX: $1.x, y: $1.y) })
                .reduce(0, combine: +)
        }
        
        func scoreLetter(letter: Character, x: Int, y: Int) {
            let value = letterPoints(letter, atX: x, y: y)
            if board.isFilledAt(x, y) {
                score += value
                return
            }
            let letterMultiplier = board.config.letterMultipliers[y][x]
            let wordMultiplier = board.config.wordMultipliers[y][x]
            tilesUsed += 1
            score += value * letterMultiplier
            scoreMultiplier *= wordMultiplier
            
            if let intersectingWord = intersectedWords.filter({ word.horizontal ? $0.x == x : $0.y == y }).first {
                // scoreWord method will score this letter once, so lets just add the remaining amount if placed on a premium square.
                let wordScore = scoreWord(intersectingWord) + (value * (letterMultiplier - 1))
                intersectionsScore += wordScore * wordMultiplier
            }
        }
        
        for (i, letter) in word.word.characters.enumerate() {
            scoreLetter(letter,
                        x: word.x + (word.horizontal ? i : 0),
                        y: word.y + (word.horizontal ? 0 : i))
        }
        
        return (score * scoreMultiplier) + intersectionsScore + (tilesUsed == 7 ? allTilesUsedBonus : 0)
    }
    
    mutating func play(solution: Solution) -> [Character] {
        let dropped = board.play(solution)
        boardState = BoardState(board: board)
        return dropped
    }
    
    // TODO: Break into smaller methods; improve reuse of 'let word = ... where word.valid == false'
    func validate(points: [(x: Int, y: Int, letter: Character)], blanks: [(x: Int, y: Int)]) -> ValidationResponse {
        if points.count == 0 || (points.count == 1 && board.isFirstPlay) {
            return .InvalidArrangement
        }
        
        let allBlanks = board.playedBlanks + blanks
        if points.count == 1 {
            let x = points.first!.x
            let y = points.first!.y
            let horizontalWord = wordAt(x, y: y, points: points, horizontal: true)
            if let word = horizontalWord where word.valid == false {
                return .invalid(withWord: word.word)
            }
            let verticalWord = wordAt(x, y: y, points: points, horizontal: false)
            if let word = verticalWord where word.valid == false {
                return .invalid(withWord: word.word)
            }
            if let word = horizontalWord?.word {
                let intersections = verticalWord != nil ? [verticalWord!.word] : []
                let score = calculateScore(word, intersectedWords: intersections, blanks: allBlanks)
                let solution = Solution(word: word, score: score, intersections: intersections, blanks: blanks)
                return .Valid(solution:solution)
            }
            else if let word = verticalWord?.word {
                let intersections = horizontalWord != nil ? [horizontalWord!.word] : []
                let score = calculateScore(word, intersectedWords: intersections, blanks: allBlanks)
                let solution = Solution(word: word, score: score, intersections: intersections, blanks: blanks)
                return .Valid(solution: solution)
            }
            return .InvalidArrangement
        }
        else {
            // Determine direction of word
            let horizontalSort = points.sort({ $0.x < $1.x })
            let verticalSort = points.sort({ $0.y < $1.y })
            
            guard let horizontalFirst = horizontalSort.first, verticalFirst = verticalSort.first else {
                return .InvalidArrangement
            }
            let isHorizontal = horizontalFirst.y == horizontalSort.last?.y
            let isVertical = verticalFirst.x == verticalSort.last?.x
            if !isHorizontal && !isVertical {
                return .InvalidArrangement
            }
            
            guard let (word, valid) = wordAt(horizontalFirst.x, y: verticalFirst.y, points: isHorizontal ? horizontalSort : verticalSort, horizontal: isHorizontal) else {
                return .InvalidArrangement
            }
            if !valid {
                return .invalid(withWord: word)
            }
            
            // Collect intersections for this word, if any are invalid lets return
            let (intersectionsValid, intersectedWords) = intersections(forWord: word)
            if !intersectionsValid {
                // If we get here we will have an intersected word (it will be the invalid one).
                return .invalid(withWord: intersectedWords.first!)
            }
            
            // First turn is only one that cannot intersect a word other plays must intersect
            if !board.isFirstPlay && intersectedWords.count == 0 {
                return .InvalidArrangement
            }
            
            // Calculate score and return solution
            let score = calculateScore(word, intersectedWords: intersectedWords, blanks: allBlanks)
            let solution = Solution(word: word, score: score, intersections: intersectedWords, blanks: blanks)
            return .Valid(solution: solution)
        }
    }
    
    func lexicographicalString(withLetters letters: [Character]) -> String {
        return String(letters.sort())
    }
    
    /// - parameter letters: Refers to the tiles in a user's rack we can use, i.e. unplayed/unfixed letters.
    /// - parameter fixedLetters: Letters already on the board.
    /// - parameter length: Length of words to find anagrams with, if length < letters + fixedLetters
    func unvalidatedWords(forLetters letters: [Character], fixedLetters: [Int: Character], length: Int) -> Anagrams? {
        // Get all letters that are possible to be used
        let anagramLetters = (letters + fixedLetters.values)
        
        // Calculate permutations, then filter any that are lexicographically equivalent to reduce work of anagram dictionary
        var combinations: [String]
        if length == anagramLetters.count {
            combinations = [anagramLetters].map(lexicographicalString)
        } else {
            combinations = Array(Set(anagramLetters.combinations(length).map(lexicographicalString)))
        }
        let anagrams = combinations.flatMap({ lookup.anagrams[$0, fixedLetters] }).flatMap({ $0 })
        return anagrams.count > 0 ? anagrams : nil
    }
    
    /// - returns: Offsets in word that are blank using a players rack tiles.
    func blanks(forWord word: Word, rackLetters: [RackTile]) -> [(x: Int, y: Int)] {
        var tempPlayer = Human(rackTiles: rackLetters)
        return word.word.characters.enumerate().flatMap({ (index, letter) in
            tempPlayer.removeLetter(letter).wasBlank ? word.position(forIndex: index) : nil
        })
    }
    
    /// - returns: `words` will contain the first invalid intersection if `valid` is `false` or the array of intersections if `valid` is `true`. `valid` should be handled appropriately.
    private func intersections(forWord word: WordRepresentation) -> (valid: Bool, words: [Word]) {
        var words = [Word]()
        for (index, letter) in word.word.characters.enumerate() {
            let pos = word.position(forIndex: index)
            if let intersectedWord = wordAt(pos.x, y: pos.y, points: [(x: pos.x, y: pos.y, letter: letter)], horizontal: !word.horizontal) {
                if !intersectedWord.valid {
                    return (false, [intersectedWord.word])
                }
                words.append(intersectedWord.word)
            }
        }
        return (true, words)
    }
    
    func solution(forWord word: Word, rackLetters: [RackTile]) -> Solution? {
        let (valid, _intersectedWords) = intersections(forWord: word)
        if !valid {
            return nil
        }
        let intersectedWords = _intersectedWords ?? []
        
        let blankSpots = blanks(forWord: word, rackLetters: rackLetters)
        let score = calculateScore(word, intersectedWords: intersectedWords, blanks: blankSpots)
        return Solution(word: word, score: score, intersections: intersectedWords, blanks: blankSpots)
    }
    
    private func solutionsAt(x x: Int, y: Int, letters: [Character], rackLetters: [RackTile], length: Int, horizontal: Bool) -> [Solution]? {
        assert((horizontal ? x : y) + length - 1 < board.config.size)
        
        if !board.isValidSpot(x, y: y, length: length, horizontal: horizontal) {
            return nil
        }
        // Is valid spot should filter these...
        let offset = boardState[horizontal][y][x]
        assert(offset == x && horizontal || offset == y && !horizontal)
        
        // Collect characters that are filled, must have at least one character to branch off of
        // Get possible words for given set of letters for this length
        guard let
            fixedLetters = charactersAt(x, y: y, length: length, horizontal: horizontal),
            words = unvalidatedWords(forLetters: letters, fixedLetters: fixedLetters, length: length) else {
            return nil
        }
        
        return words.flatMap({ solution(forWord: Word(word: $0, x: x, y: y, horizontal: horizontal), rackLetters: rackLetters) })
    }
    
    func solutions(letters: [RackTile], serial: Bool = false, completion: ([Solution]?) -> ()) {
        if letters.count == 0 {
            completion(nil)
            return
        }
        
        let solutionLetters = letters.map({ $0.letter })
        var solutions = [Solution]()
        var count = 0
        let range = board.config.boardRange
        let size = board.config.size
        for length in 2...maximumWordLength {
            count += 1
            let effectiveRange = (0...(size - length))
            if serial {
                for x in range {
                    for y in range {
                        if effectiveRange.contains(x) {
                            if let solves = solutionsAt(x: x, y: y, letters: solutionLetters, rackLetters: letters, length: length, horizontal: true) {
                                solutions += solves
                            }
                        }
                        if effectiveRange.contains(y) {
                            if let solves = solutionsAt(x: x, y: y, letters: solutionLetters, rackLetters: letters, length: length, horizontal: false) {
                                solutions += solves
                            }
                        }
                    }
                }
            } else {
                let currentQueue = NSOperationQueue.currentQueue()
                operationQueue.addOperationWithBlock({
                    var innerSolutions = [Solution]()
                    for x in range {
                        for y in range {
                            if effectiveRange.contains(x) {
                                if let solves = self.solutionsAt(x: x, y: y, letters: solutionLetters, rackLetters: letters, length: length, horizontal: true) {
                                    innerSolutions += solves
                                }
                            }
                            if effectiveRange.contains(y) {
                                if let solves = self.solutionsAt(x: x, y: y, letters: solutionLetters, rackLetters: letters, length: length, horizontal: false) {
                                    innerSolutions += solves
                                }
                            }
                        }
                    }
                    currentQueue?.addOperationWithBlock({
                        solutions += innerSolutions
                        count -= 1
                        if count == 0 {
                            completion(solutions)
                        }
                    })
                })
            }
        }
        
        if serial {
            completion(solutions.count > 0 ? solutions : nil)
        }
    }
    
    func solve(solutions: [Solution], difficulty: Difficulty = .Hard) -> Solution? {
        if solutions.count == 0 {
            return nil
        }
        let best = solutions.sort({ $0.score < $1.score }).last!
        if difficulty == .Hard {
            return best
        }
        let scaled = Double(best.score) * difficulty.rawValue
        var suitable: (difference: Double, solution: Solution)?
        // Smallest difference = solution to play
        for solution in solutions where Double(solution.score) < scaled {
            let diff = abs(scaled - Double(solution.score))
            if suitable == nil {
                suitable = (diff, solution)
                continue
            }
            if min(abs(suitable!.difference), diff) == diff {
                suitable = (diff, solution)
            }
        }
        return suitable?.solution ?? best
    }
}

