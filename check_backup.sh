#!/usr/bin/env bash
set -euo pipefail

echo "=============================="
echo "🔎 فحص النسخ والرفع - Git Health"
echo "=============================="

# 1) تأكد أننا داخل مستودع Git
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "❌ لست داخل مجلد مشروع Git"
  exit 1
fi

# 2) معلومات عامة
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "📌 الفرع الحالي: $CURRENT_BRANCH"

# 3) هل يوجد remote origin؟
if git remote get-url origin >/dev/null 2>&1; then
  ORIGIN_URL="$(git remote get-url origin)"
  echo "🌐 origin: $ORIGIN_URL"
else
  echo "❌ لا يوجد remote اسمه origin. استخدم:"
  echo "   git remote add origin https://github.com/USER/REPO.git"
  exit 1
fi

# 4) تحديث معلومات الفروع البعيدة
git fetch --all --prune >/dev/null 2>&1 || true

# 5) وجود فروع إنقاذ محلية
RESCUE_LOCAL="$(git branch --list 'rescue/*' || true)"
if [[ -n "$RESCUE_LOCAL" ]]; then
  echo "🛟 نسخ احتياطية محلية موجودة:"
  echo "$RESCUE_LOCAL"
else
  echo "⚠️ لا توجد فروع احتياطية محلية باسم rescue/*"
fi

# 6) وجود فروع إنقاذ على GitHub
RESCUE_REMOTE="$(git branch -r | grep 'origin/rescue/' || true)"
if [[ -n "$RESCUE_REMOTE" ]]; then
  echo "☁️ نسخ احتياطية مرفوعة على GitHub:"
  echo "$RESCUE_REMOTE"
else
  echo "⚠️ لا توجد نسخ احتياطية على GitHub (origin/rescue/*)."
  echo "   لرفع فرع إنقاذ: git push -u origin rescue/backup-YYYY-MM-DD-HHMM"
fi

# 7) حالة التعديلات غير المحفوظة
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "❗ لديك تعديلات غير محفوظة (commit) في هذا الفرع."
  echo "   نفِّذ: git add -A && git commit -m \"حفظ التعديلات\""
else
  echo "✅ لا توجد تعديلات غير محفوظة في الفرع الحالي."
fi

# 8) التحقق من main محليًا وبعيدًا
HAS_MAIN_LOCAL=0
HAS_MAIN_REMOTE=0
git show-ref --verify --quiet refs/heads/main && HAS_MAIN_LOCAL=1 || true
git show-ref --verify --quiet refs/remotes/origin/main && HAS_MAIN_REMOTE=1 || true

if [[ "$HAS_MAIN_LOCAL" -eq 1 ]]; then
  echo "📁 main موجود محليًا."
else
  echo "⚠️ main غير موجود محليًا. لإنشائه من الحالة الحالية:"
  echo "   git checkout -b main"
fi

if [[ "$HAS_MAIN_REMOTE" -eq 1 ]]; then
  echo "☁️ origin/main موجود على GitHub."
else
  echo "⚠️ لا يوجد origin/main على GitHub. لإنشائه:"
  echo "   git checkout -B main && git push -u origin main"
fi

# 9) هل لدى الفرع الحالي التغييرات مرفوعة؟
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
if [[ -z "$UPSTREAM" ]]; then
  echo "⚠️ الفرع الحالي لا يملك upstream (تتبّع)."
  echo "   لتعيينه: git push -u origin $CURRENT_BRANCH"
else
  AHEAD="$(git rev-list --left-right --count $UPSTREAM...$CURRENT_BRANCH | awk '{print $2}')"
  BEHIND="$(git rev-list --left-right --count $UPSTREAM...$CURRENT_BRANCH | awk '{print $1}')"
  echo "🔁 مقارنة بالـ upstream ($UPSTREAM): Ahead=$AHEAD Behind=$BEHIND"
  if [[ "$AHEAD" -gt 0 ]]; then
    echo "⚠️ لديك التزامات محلية غير مرفوعة. نفِّذ: git push"
  fi
  if [[ "$BEHIND" -gt 0 ]]; then
    echo "⚠️ الفرع متأخر عن GitHub. نفِّذ: git pull --rebase"
  fi
fi

# 10) لمحة عن آخر الالتزامات في main (إن وجدت)
if [[ "$HAS_MAIN_LOCAL" -eq 1 ]]; then
  echo "🧾 آخر التزامات في main (محليًا):"
  git log main --oneline -3 || true
fi
if [[ "$HAS_MAIN_REMOTE" -eq 1 ]]; then
  echo "🧾 آخر التزامات في origin/main:"
  git log origin/main --oneline -3 || true
fi

echo "=============================="
echo "✅ انتهى فحص الصحة."
