with open('lib/screens/coach_selection_screen.dart', 'r', encoding='utf-8', errors='ignore') as f:
    lines = f.readlines()

new_lines = lines[:576]
new_lines.append("}\n")

with open('lib/screens/coach_selection_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
