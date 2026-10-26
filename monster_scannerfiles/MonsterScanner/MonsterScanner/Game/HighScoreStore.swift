import Foundation

/// Persists the all-time bests across launches. Tiny on purpose: two integers in `UserDefaults`.
struct HighScoreStore {
    struct Records: Equatable {
        var highScore = 0
        var bestStreak = 0
        var totalMonstersFound = 0
    }

    private enum Key {
        static let highScore = "game.highScore"
        static let bestStreak = "game.bestStreak"
        static let totalMonsters = "game.totalMonstersFound"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Records {
        Records(highScore: defaults.integer(forKey: Key.highScore),
                bestStreak: defaults.integer(forKey: Key.bestStreak),
                totalMonstersFound: defaults.integer(forKey: Key.totalMonsters))
    }

    /// Merges a run into the stored records (keeps maxima, adds totals) and returns the result.
    @discardableResult
    func record(score: Int, bestStreak: Int, newMonstersFound: Int) -> Records {
        var records = load()
        records.highScore = max(records.highScore, score)
        records.bestStreak = max(records.bestStreak, bestStreak)
        records.totalMonstersFound += newMonstersFound
        defaults.set(records.highScore, forKey: Key.highScore)
        defaults.set(records.bestStreak, forKey: Key.bestStreak)
        defaults.set(records.totalMonstersFound, forKey: Key.totalMonsters)
        Log.game.debug("Records saved: high \(records.highScore), streak \(records.bestStreak), total \(records.totalMonstersFound)")
        return records
    }
}
