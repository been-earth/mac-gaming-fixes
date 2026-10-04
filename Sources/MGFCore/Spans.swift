/// Column spans for the 6-column feature grid, chosen so that every row is full whatever the
/// category filter leaves. Fixes sit three to a row, tools two to a row; leftovers stretch.
public func gridSpans(_ kinds: [Bool]) -> [Int] {  // true = fix, false = tool; fixes come first
    let fixes = kinds.filter { $0 }.count, tools = kinds.count - fixes
    var out = [Int](repeating: 2, count: fixes) + [Int](repeating: 3, count: tools)
    let loneFixes = fixes % 3, loneTool = tools % 2 == 1
    if loneFixes == 2 { out[fixes - 1] = 3; out[fixes - 2] = 3 }
    if loneFixes == 1 { out[fixes - 1] = loneTool ? 3 : 6 }  // 3: shares its row with the first tool
    if loneTool, loneFixes != 1 { out[out.count - 1] = 6 }
    return out
}

/// The same spans cut into rows of 6.
public func gridRows(_ kinds: [Bool]) -> [Range<Int>] {
    var rows: [Range<Int>] = [], start = 0, width = 0
    for (i, span) in gridSpans(kinds).enumerated() {
        width += span
        if width >= 6 { rows.append(start..<i + 1); start = i + 1; width = 0 }
    }
    return rows
}
