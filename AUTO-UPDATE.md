# به‌روزرسانی امن مخزن MCP For Blender

این پوشه یک کلون کامل از ریپوی [ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender) است.
شاخه فعال: `main` (tracking: `origin/main`).

## رفتار اسکریپت

`update.ps1` اول `git fetch` می‌زند و اگر کامیت جدیدی آمده باشد:

1. هر فایلی که **شما تغییر داده‌اید** (تغییر uncommitted یا staged) را با نام
   `<نام فایل>_cloneUpdated_<تاریخ شمسی><پسوند>` کنار می‌گذارد؛ مثلاً:

   ```
   main.py                  ->  main_cloneUpdated_1405-08-14.py
   src/server.py            ->  src/server_cloneUpdated_1405-08-14.py
   Dockerfile               ->  Dockerfile_cloneUpdated_1405-08-14
   ```

   محتوای فایل شما عیناً در فایل `_cloneUpdated_...` باقی می‌ماند.
2. فایل اصلی را به نسخه‌ی ریپو برمی‌گرداند، سپس به‌صورت fast-forward به‌روز می‌کند.
   اگر بعد از به‌روزرسانی هم فایل تغییر کرده باشد، نسخه‌ی جدید ریپو سر جایش می‌آید.
3. فایل‌های **untracked** که نامشان با فایل‌های جدید ریپو تصادم کند هم به همین شکل
   کنار گذاشته می‌شوند تا git آن‌ها را بازنویسی نکند.
4. فایل‌های untracked دیگر (که با آپدیت تصادم ندارند) کاملاً دست‌نخورده می‌مانند.
5. اگر آپدیتی موجود نباشد، هیچ فایلی تغییر نام نمی‌دهد و تغییرات شما سر جایشان می‌مانند.

اگر در یک روز چند بار آپدیت اجرا شود و نام تکراری باشد، پسوند شماره‌دار می‌شود:
`..._cloneUpdated_1405-08-14-2.py`، `-3` و الی آخر. تاریخ شمسی از تقویم فارسی
ویندوز (PersianCalendar) گرفته می‌شود.

> فایل‌های `_cloneUpdated_...` را خودتان پاک/جابه‌جا کنید؛ اسکریپت هیچ‌وقت آن‌ها را
> حذف نمی‌کند (ولی `git clean -fd` آن‌ها را پاک می‌کند، مراقب باشید).

## اجرای دستی

- دابل‌کلیک روی `update.cmd` (پنجره باز می‌ماند تا نتیجه را ببینید)، یا:

```powershell
.\update.ps1          # امن: تغییرات شما را با نام _cloneUpdated_<تاریخ شمسی> نگه می‌دارد
.\update.ps1 -Hard    # خطرناک: بدون هیچ بکاپی تغییرات فایل‌های تحت git را دور می‌ریزد
.\update.ps1 -Quiet   # خروجی کم (مناسب برای اجرای زمان‌بندی‌شده)
```

خروجی صفر یعنی «به‌روز است یا به‌روز شد» و خروجی یک یعنی خطا. اسکریپت هیچ‌وقت
کامیت محلی نمی‌سازد و merge غیر fast-forward انجام نمی‌دهد.

## به‌روزرسانی کاملاً خودکار (بدون ایجنت)

برای اجرای روزانه، یک Task در Windows Task Scheduler بسازید (بدون نیاز به ادمین):

```powershell
$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-NoProfile -ExecutionPolicy Bypass -File "D:\Airis\Agents\MCP\MCP For Blender\update.ps1" -Quiet'
$trigger = New-ScheduledTaskTrigger -Daily -At 09:00
Register-ScheduledTask -TaskName 'MCP For Blender Auto-Update' `
           -Action $action -Trigger $trigger -Description 'Daily git pull for MCP For Blender clone'
```

حذف / اجرای دستی:

```powershell
Unregister-ScheduledTask -TaskName 'MCP For Blender Auto-Update' -Confirm:$false
Start-ScheduledTask     -TaskName 'MCP For Blender Auto-Update'
```

## ساختار مخزن

| مسیر | توضیح |
| --- | --- |
| `addon.py` | افزونه Blender |
| `main.py` / `src/` | سرور MCP |
| `install.ps1` / `install.sh` | نصب‌کننده پروژه |
| `update.ps1` / `update.cmd` | اسکریپت به‌روزرسانی (خارج از ریپو) |
| `*_cloneUpdated_<تاریخ>` | نسخه‌های محلی شما که اسکریپت کنار گذاشته است |

سه فایل کمکی در `.git/info/exclude` هستند تا در `git status` مزاحم نشوند.
