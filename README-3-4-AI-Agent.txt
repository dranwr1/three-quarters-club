# 3/4 AI Agent — المرحلة الأولى

هذه الحزمة تضيف واجهة المساعد الذكي إلى الموقع، ودالة Supabase آمنة تتصل بـ OpenAI Responses API. النسخة الأولى **للقراءة والتحليل والاقتراح فقط**؛ لا تعدّل الكتب أو تقدم الأعضاء ولا تكتب إلى GitHub.

## الملفات
- `3-4-reading-club-ai.html`: نسخة الموقع مع واجهة المساعد.
- `supabase/functions/club-agent/index.ts`: دالة الخادم التي تتحقق من جلسة المستخدم، تقرأ حقولًا غير حساسة من `books` و`profiles`، ثم ترسل السؤال إلى Responses API.

## إعداد Supabase
1. افتح مشروع Supabase ثم Edge Functions.
2. أنشئ Function باسم `club-agent` والصق محتوى `supabase/functions/club-agent/index.ts`، أو انشرها باستخدام Supabase CLI.
3. اضبط الأسرار التالية في إعدادات Edge Function / Secrets:
   - `OPENAI_API_KEY` = مفتاح API الخاص بك.
   - `OPENAI_MODEL` = `gpt-6-luna` (يمكن تغييره إلى نموذج متاح لحساب API).
   - `SUPABASE_SERVICE_ROLE_KEY` = service role key للمشروع (سر خادمي فقط).
   - `SUPABASE_URL` و`SUPABASE_ANON_KEY` متاحان عادة كمتغيرات بيئة في Supabase Functions؛ أضفهما يدويًا فقط إذا لم يكونا متاحين.
4. لا تضع `OPENAI_API_KEY` أو `SUPABASE_SERVICE_ROLE_KEY` في HTML أو GitHub Pages أو أي كود يصل للمتصفح.
5. لا تعطّل التحقق من JWT للدالة. الواجهة ترسل جلسة المستخدم تلقائيًا.
6. ارفع `3-4-reading-club-ai.html` بدل ملف الصفحة الرئيسية بعد الاحتفاظ بنسخة احتياطية. إذا كان GitHub Pages يعرض `index.html`، غيّر اسم النسخة إلى `index.html` قبل رفعها.

## ملاحظات قبل التشغيل
- الدالة تتحقق من هوية العضو قبل استخدام مفتاح الخدمة.
- تُقرأ فقط الحقول `title, author, category, pages, status, notes, created_at` من الكتب و`full_name, username` من الأعضاء. لا تُقرأ عناوين البريد أو بيانات المصادقة.
- يجب مراجعة سياسات الوصول (RLS) وجداول المشروع الفعلية. الدالة الحالية تفترض وجود جدول `books` بهذه الحقول وجدول `profiles` بحقول `full_name` و`username`.
- لا توجد محادثات دائمة بعد؛ سجل المحادثة محفوظ مؤقتًا في الصفحة الحالية فقط.
- المرحلة التالية: أدوات محدودة للوكيل لإضافة كتاب أو تحديث تقدم القراءة بموافقة العضو، ثم صلاحيات إدارية منفصلة، ثم مراجعة تغييرات الموقع عبر Pull Request بدل تعديل مباشر.

## نشر عبر Supabase CLI (اختياري)
```bash
supabase functions deploy club-agent
supabase secrets set OPENAI_API_KEY=YOUR_KEY OPENAI_MODEL=gpt-6-luna SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
```
