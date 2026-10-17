# GiftWallet – Harvester

מערכת שאוספת כל יום את רשימת בתי העסק שמכבדים את הכרטיסים שלך, ושומרת אותה כקבצי JSON שהאפליקציה באייפון תקרא.

## מה נאסף

| כרטיס | מקור | מה מקבלים |
|---|---|---|
| **BUYME ALL** | ה-JSON שעמוד "בתי עסק מכבדים" של BuyMe טוען (`buyme.co.il/brands/13438757/options`) | כ-1,300 עסקים: שם, קטגוריה ותת-קטגוריות, אזורים, טלפון, אתר, קישור לאיתור סניפים, תנאי מימוש, מימוש אונליין, וכתובת לעסקים עם סניף יחיד |
| **DREAM CARD** | עמוד "תווי השי שלנו" ב-dcgift.co.il | כ-20 רשתות של קבוצת FOX, עם הערות מימוש (למשל NIKE) |

**כתובות:** עסקים עם סניף אחד (מסעדות, ספא וכו', כ-600) מקבלים קואורדינטות דרך OpenStreetMap, עם מטמון בקובץ `data/geocache.json`. ריצה אחת מעבדת עד 400 כתובות חדשות, כך שהמטמון מתמלא במלואו אחרי יומיים.
**רשתות** (FOX, adidas, קסטרו...) לא מקבלות קואורדינטות מראש. האפליקציה תמצא את הסניף הקרוב בזמן אמת דרך חיפוש Apple Maps.

## קבצי הפלט (`data/`)

- `cards.json` – הכרטיסים הנתמכים ותנאים כלליים
- `merchants.json` – רשומה אחת לכל עסק וכרטיס. השדה `brand_key` מאפשר לזהות את אותו מותג גם כשהוא מופיע בכמה כרטיסים
- `changes.json` – מה נוסף או הוסר מאז הריצה הקודמת. מכאן יגיעו התראות כמו "עסק חדש מכבד את הכרטיס שלך"
- `meta.json` – זמן הריצה, ספירות, ומקורות שנכשלו

אם מקור מסוים נכשל, הנתונים הקודמים שלו נשמרים ולא נמחקים. אם BuyMe מחזיר פחות מ-50 עסקים, הריצה עוצרת ולא דורסת את הנתונים.

## התקנה ב-GitHub (חד-פעמי)

1. ב-GitHub: **New repository** → שם לדוגמה `giftwallet` → **Public**. ב-repo ציבורי, Actions חינמי בלי הגבלת דקות, והאפליקציה תוכל לקרוא את הקבצים בלי טוקן.
2. העלה את כל תוכן התיקייה. אפשר לגרור ל-**Add file → Upload files**, ואפשר ב-git:
   ```bash
   git init && git add . && git commit -m "harvester"
   git branch -M main
   git remote add origin https://github.com/<user>/giftwallet.git
   git push -u origin main
   ```
3. **Settings → Actions → General → Workflow permissions** → סמן **Read and write permissions** → Save.
4. **Actions → Harvest gift-card merchants → Run workflow**. הריצה הראשונה לוקחת כ-8 דקות, בגלל הקואורדינטות.

מכאן והלאה הריצה אוטומטית כל לילה ב-03:15. האפליקציה תקרא את הנתונים מכתובת כזו:
`https://raw.githubusercontent.com/<user>/giftwallet/main/data/merchants.json`

## הרצה מקומית

```bash
pip install -r requirements.txt
python -m pytest -q                 # בדיקות
python -m harvester.run --no-geo    # ריצה מהירה בלי קואורדינטות
```

## הוספת כרטיס

- **כרטיס BuyMe נוסף** (STYLE, CHEF וכו'): פותחים ב-buyme.co.il את עמוד הכרטיס, לוקחים את המספר מהכתובת (`/supplier/<מספר>`), ומוסיפים שורה ל-`CARDS` בקובץ `harvester/run.py`.
- **מנפיק אחר** (תו הזהב, ויקטורי...): מוסיפים קובץ חדש תחת `harvester/sources/` שמחזיר רשימת `Merchant`.

## הערה

ה-Harvester שולח בקשה אחת ביום לכל מקור, ומזדהה בצורה מסודרת מול OpenStreetMap. הנתונים מיועדים לשימוש אישי. רשימת העסקים של BuyMe משתנה מדי פעם, ולכן לפני מימוש כדאי לוודא באפליקציית BuyMe.
