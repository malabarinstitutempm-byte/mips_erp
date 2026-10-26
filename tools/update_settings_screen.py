with open('E:/mips_erp/lib/features/settings/settings_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

target = "? 'Project URL: ${SupabaseService.instance.url}'"
replacement = "? 'Project Ref: evzehywyyqmcktszwmeg • URL: ${SupabaseService.instance.url}'"

if target in content:
    content = content.replace(target, replacement, 1)
    with open('E:/mips_erp/lib/features/settings/settings_screen.dart', 'w', encoding='utf-8') as f:
        f.write(content)
    print("Replaced successfully")
else:
    print("Target not found in settings_screen.dart")
