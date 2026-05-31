with open('lib/l10n/l10n.dart') as f:
    content = f.read()

# Add original Chinese keys to _en for backward compatibility
# These keys exist in _zh but were missing from _en
new_en_backfill = '''
    // Backward compatibility: original Chinese keys -> English translations
    '\u4e91\u540c\u6b65\u5931\u8d25\u4e0d\u4f1a\u963b\u65ad\u5b66\u4e60_\u672c\u5730\u4e8b\u4ef6\u4f1a\u7b49\u5f85\u91cd\u8bd5': 'Cloud sync failure will not block learning, local events will wait for retry.',
    '\u4eca\u65e5\u590d\u4e60': 'Today Review',
    '\u4eca\u65e5\u590d\u4e60\u5df2\u5b8c\u6210': 'Today Review Complete!',
    '\u4eca\u65e5\u590d\u4e60\u961f\u5217': 'Today Review Queue',
    '\u6e05\u7406\u4eca\u65e5\u590d\u4e60': 'Clear Today Review',
    '\u7981\u7528\u7684\u9886\u57df\u4e0d\u4f1a\u5728\u9996\u9875\u663e\u793a_\u4f46\u5185\u5bb9\u4e0d\u4f1a\u88ab\u5220\u9664': 'Disabled domains will not be shown on the home page, but content will not be deleted',
'''

# Find position to insert - before the closing } of _en
en_close = content.rfind('  };\n\n  static String get(String key,')
# Find the last non-blank, non-comment line before the closing brace
# Go backwards from en_close to find the last entry line
back_part = content[:en_close]
last_quote = back_part.rfind("'")
last_comma = back_part.rfind(",", 0, last_quote)
if last_comma > 0:
    insert_pos = last_comma + 1
    new_content = content[:insert_pos] + ',' + new_en_backfill + content[insert_pos:]
else:
    new_content = content[:en_close] + new_en_backfill + '\n' + content[en_close:]

with open('lib/l10n/l10n.dart', 'w') as f:
    f.write(new_content)

print('Done - added backward-compat Chinese keys to _en map')
