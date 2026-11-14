# 3/4 AI Agent — المرحلة الأولى

تستخدم واجهة الموقع دالة Supabase باسم `club-agent` للاتصال بـ OpenAI Chat Completions باستخدام نموذج `gpt-4o-mini`. لا تضع مفاتيح الخدمة في المتصفح.

## الملفات
- `index.html`: واجهة الموقع التي تستدعي `club-agent`.
- `supabase/functions/club-agent/index.ts`: دالة الخادم التي تتحقق من جلسة المستخدم وتستخدم `OPENAI_API_KEY` من أسرار Supabase.

## إعداد Supabase
1. افتح مشروع Supabase ثم Edge Functions.
2. أنشئ Function باسم `club-agent` والصق محتوى `supabase/functions/club-agent/index.ts`، أو انشرها باستخدام Supabase CLI.
3. اضبط الأسرار التالية في إعدادات Edge Function / Secrets:
   - `OPENAI_API_KEY` = مفتاح OpenAI الذي تقرؤه الدالة عبر `Deno.env.get("OPENAI_API_KEY")`.
   - `SUPABASE_SERVICE_ROLE_KEY` = service role key للمشروع (سر خادمي فقط).
   - `SUPABASE_URL` و`SUPABASE_ANON_KEY` متاحان عادة كمتغيرات بيئة في Supabase Functions؛ أضفهما يدويًا فقط إذا لم يكونا متاحين.
4. لا تضع `OPENAI_API_KEY` أو `SUPABASE_SERVICE_ROLE_KEY` في HTML أو GitHub Pages أو أي كود يصل للمتصفح.
5. تستدعي الواجهة الدالة باسم `club-agent` وترسل جلسة المستخدم؛ تتحقق الدالة من الجلسة قبل تنفيذ الطلب.
6. انشر نسخة الموقع من `index.html` بالطريقة المعتادة.

## ملاحظات قبل التشغيل
- الدالة تتحقق من جلسة المستخدم قبل استخدام مفتاح الخدمة.
- تعتمد الوظائف الحالية على جداول `books` و`members` و`book_reading_progress` و`book_court_*` و`book_margin_notes*`؛ تأكد من توافق المخطط المنشور معها.
- لا توجد محادثات دائمة بعد؛ سجل المحادثة محفوظ مؤقتًا في الصفحة الحالية فقط.
- المرحلة التالية: أدوات محدودة للوكيل لإضافة كتاب أو تحديث تقدم القراءة بموافقة العضو، ثم صلاحيات إدارية منفصلة، ثم مراجعة تغييرات الموقع عبر Pull Request بدل تعديل مباشر.

## النشر عبر Supabase CLI
```bash
supabase functions deploy club-agent --project-ref YOUR_PROJECT_REF
```
تحقق من وجود اسم `OPENAI_API_KEY` في إعدادات Secrets بلوحة Supabase، ولا تكشف قيمته في السجلات أو المتصفح.
