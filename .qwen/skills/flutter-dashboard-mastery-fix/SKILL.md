---
name: flutter-dashboard-mastery-fix
description: Fixing Flutter dashboard mastery display issues - layout conflicts, threshold inconsistencies, and data structure problems
source: auto-skill
extracted_at: '2026-05-31T12:00:00.000Z'
---

# Flutter Dashboard Mastery Display Fix

## When to use
- Dashboard mastery overview shows white/blank areas
- Mastery thresholds are inconsistent across components (>=80 vs >=85)
- Mastery display structure doesn't match intended design
- Route/domain selection buttons are blocked by other UI elements

## Common Issues and Solutions

### Issue 1: White Screen in Mastery Stats Cards
**Symptom**: `_MasteryStats` shows blank white scrolling areas
**Root Cause**: `Expanded` widget inside `SizedBox` causes layout conflict
**Solution**: Remove `Expanded` wrapper from `_MasteryStatCard`:
```dart
// WRONG - Expanded inside SizedBox causes layout conflict
return SizedBox(
  width: cardWidth,
  child: Expanded(  // ← Remove this
    child: Container(...)
  ),
);

// CORRECT - Container directly inside SizedBox
return SizedBox(
  width: cardWidth,
  child: Container(...)
);
```

### Issue 2: Mastery Display Structure Mismatch
**Symptom**: Shows individual category percentages instead of mastery level breakdown
**Root Cause**: `_MasteryOverview` receives `categories` list but should show mastery levels
**Solution**: 
1. Change `_MasteryOverview` to accept mastery level percentages:
```dart
class _MasteryOverview extends StatelessWidget {
  const _MasteryOverview({
    required this.masteryPercent,
    required this.masteredPercent,  // % of topics with score >= 85
    required this.learningPercent,  // % of topics with score >= 60
    required this.newPercent,       // % of topics with score < 60
  });
```

2. Calculate mastery levels in parent widget:
```dart
int totalTopics = domainTopics.length;
int masteredCount = 0, learningCount = 0, newCount = 0;

for (final topic in domainTopics) {
  final score = progressProvider.getTopicProgress(topic.id)?.score ?? 0;
  if (score >= 85) masteredCount++;
  else if (score >= 60) learningCount++;
  else newCount++;
}

final masteredPercent = totalTopics == 0 ? 0 : (masteredCount * 100 ~/ totalTopics);
final learningPercent = totalTopics == 0 ? 0 : (learningCount * 100 ~/ totalTopics);
final newPercent = totalTopics == 0 ? 0 : (newCount * 100 ~/ totalTopics);
```

### Issue 3: Inconsistent Mastery Thresholds
**Symptom**: Same topic shows different mastery status in different components
**Root Cause**: Multiple threshold values (>=80, >=85, >=60, >=40) across files
**Solution**: Unify to standard thresholds:
- **>= 85**: 熟练 (Mastered) - Green
- **>= 60**: 学习中 (Learning) - Orange/Accent  
- **< 60**: 未掌握 (Not mastered) - Grey/Warning

Apply consistently in:
- `_MasteryStats` cards
- `_MasteryOverview` level breakdown
- `ScoreBadge` widget
- `StatusDot` widget
- `ProgressProvider` calculations

### Issue 4: Route Delete Button Blocked
**Symptom**: Cannot click delete button on route items in editor
**Root Cause**: Drag handle icon too close to delete button, tap targets overlap
**Solution**: Increase spacing and use InkWell for better tap target:
```dart
Row(
  children: [
    const Icon(Icons.drag_handle, size: 16, color: AppColors.accent),
    const SizedBox(width: 12),  // Increased from 8
    Expanded(child: Text(domain.title)),
    const SizedBox(width: 8),   // Added spacing
    InkWell(
      onTap: () => setState(() => _selectedDomainIds.removeAt(index)),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4),  // Larger tap target
        child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
      ),
    ),
  ],
)
```

## Diagnostic Checklist

When mastery display issues are reported:

1. **Check threshold consistency**: Grep for `>= 80`, `>= 85`, `>= 60` across all mastery-related files
2. **Check layout widgets**: Look for `Expanded` inside `SizedBox` or `Container` with fixed width
3. **Check data flow**: Verify what data `_MasteryOverview` receives vs what it should display
4. **Check calculation logic**: Ensure mastery percentages are calculated correctly (not just averages)
5. **Check git log**: See if recent commits changed mastery-related code

## Key Files
- `dashboard_page.dart` - Main dashboard with mastery overview
- `mastery_page.dart` - Dedicated mastery page
- `progress_provider.dart` - Mastery calculation logic
- `score_badge.dart` - Score display widget
- `status_dot.dart` - Status indicator widget

## Testing Approach
1. Run `flutter analyze` to check for compilation errors
2. Test with domains that have varying mastery levels (0%, 50%, 85%+)
3. Test with empty domains (no topics learned)
4. Test route editor with multiple custom routes
5. Verify thresholds match across all components
