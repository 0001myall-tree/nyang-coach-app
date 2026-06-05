import re

with open('lib/screens/coach_selection_screen.dart', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Replace the broken godlife_bro entry and masterCoaches
content = re.sub(
    r"'id': 'godlife_bro',.*?List<Map<String, dynamic>> get _masterCoaches => \[",
    """'id': 'bro',
      'name': '갓생 형 코치',
      'subtitle': '"형이 같이 달려줄게. 가자!"',
      'image': 'assets/images/bro.png',
      'color': const Color(0xFF03C75A),
      'price': '₩2,900 / 1년 이용',
    },
  ];

  List<Map<String, dynamic>> get _masterCoaches => [""",
    content,
    flags=re.DOTALL
)

with open('lib/screens/coach_selection_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
