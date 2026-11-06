import ItdaCore

/// What a ghost is worth against what was really typed next. Exact match: a good paraphrase scores zero.
struct Score: Equatable {
    /// The first word is exactly the next word typed.
    var useful = false
    /// Characters and keystrokes saved by Tab once, accepting the next word only.
    var tabChars = 0, tabKeys = 0
    /// By Tab repeated, as far as whole words stay right.
    var wordsChars = 0, wordsKeys = 0
    /// By accepting everything at once, zero unless all of it is right.
    var allChars = 0, allKeys = 0
    /// Leading characters right, whole word or not: 좋아요 against 좋아 is wrong but close.
    var sameChars = 0
}

/// `rest` is the true text after `committed`, including whatever the composing character will turn out to be.
func score(_ ghost: Ghost, typed: String, rest: String) -> Score {
    let shown = Array(ghost.composing + ghost.remainder), truth = Array(rest)
    let same = zip(shown, truth).prefix { $0 == $1 }.count
    // A place both texts could end a word. A word cut short by the end of the ghost doesn't count: it isn't whole.
    func wholeWord(_ n: Int) -> Bool {
        (n == truth.count || !Word.isPart(truth[n])) && (n == shown.count || !Word.isPart(shown[n]))
    }
    func saved(_ n: Int) -> (chars: Int, keys: Int) {
        let text = String(shown[..<n])
        return (max(n - typed.count, 0), max(Hangul.keys(text).count - Hangul.keys(typed).count, 0))
    }
    var out = Score(sameChars: same)
    let firstEnd = ghost.composing.count + ghost.remainder.distance(from: ghost.remainder.startIndex, to: Word.firstEnd(ghost.remainder))
    if firstEnd <= same, wholeWord(firstEnd) {
        out.useful = true
        (out.tabChars, out.tabKeys) = saved(firstEnd)
    }
    if let n = (0...same).last(where: { $0 >= firstEnd && wholeWord($0) }), out.useful {
        (out.wordsChars, out.wordsKeys) = saved(n)
    }
    if same == shown.count, wholeWord(same) { (out.allChars, out.allKeys) = saved(same) }
    return out
}
