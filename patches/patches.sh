#!/bin/bash
# Patches author: weishu <twsxtd@gmail.com>
# Shell authon: xiaoleGun <1592501605@qq.com>
#               bdqllW <bdqllT@gmail.com>
# Tested kernel versions: 5.4, 4.19, 4.14, 4.9
# 20240123

patch_files=(
    fs/exec.c
    fs/open.c
    fs/read_write.c
    fs/stat.c
    drivers/input/input.c
)

for i in "${patch_files[@]}"; do

    if grep -q "ksu" "$i"; then
        echo "Warning: $i contains KernelSU"
        continue
    fi

    case $i in

    # fs/ changes
    ## exec.c
    fs/exec.c)
        sed -i '/static int do_execveat_common/i\#ifdef CONFIG_KSU\nextern bool ksu_execveat_hook __read_mostly;\nextern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,\n			void *envp, int *flags);\nextern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,\n				 void *argv, void *envp, int *flags);\n#endif' fs/exec.c
        if grep -q "return __do_execve_file(fd, filename, argv, envp, flags, NULL);" fs/exec.c; then
            sed -i '/return __do_execve_file(fd, filename, argv, envp, flags, NULL);/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        else
            sed -i '/if (IS_ERR(filename))/i\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_execveat_hook))\n		ksu_handle_execveat(&fd, &filename, &argv, &envp, &flags);\n	else\n		ksu_handle_execveat_sucompat(&fd, &filename, &argv, &envp, &flags);\n	#endif' fs/exec.c
        fi
        ;;

    ## open.c
    fs/open.c)
        if grep -q "long do_faccessat(int dfd, const char __user \*filename, int mode)" fs/open.c; then
            sed -i '/long do_faccessat(int dfd, const char __user \*filename, int mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        else
            sed -i '/SYSCALL_DEFINE3(faccessat, int, dfd, const char __user \*, filename, int, mode)/i\#ifdef CONFIG_KSU\nextern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode,\n			 int *flags);\n#endif' fs/open.c
        fi
        sed -i '/if (mode & ~S_IRWXO)/i\	#ifdef CONFIG_KSU\n	ksu_handle_faccessat(&dfd, &filename, &mode, NULL);\n	#endif\n' fs/open.c
        ;;

    ## read_write.c
    fs/read_write.c)
        sed -i '/ssize_t vfs_read(struct file/i\#ifdef CONFIG_KSU\nextern bool ksu_vfs_read_hook __read_mostly;\nextern int ksu_handle_vfs_read(struct file **file_ptr, char __user **buf_ptr,\n		size_t *count_ptr, loff_t **pos);\n#endif' fs/read_write.c
        sed -i '/ssize_t vfs_read(struct file/,/ssize_t ret;/{/ssize_t ret;/a\
        #ifdef CONFIG_KSU\
        if (unlikely(ksu_vfs_read_hook))\
            ksu_handle_vfs_read(&file, &buf, &count, &pos);\
        #endif
        }' fs/read_write.c
        ;;

    ## stat.c
    fs/stat.c)
        if grep -q "int vfs_statx(int dfd, const char __user \*filename, int flags," fs/stat.c; then
            sed -i '/int vfs_statx(int dfd, const char __user \*filename, int flags,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif' fs/stat.c
            sed -i '/unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\\n	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flags);\n	#endif' fs/stat.c
        else
            sed -i '/int vfs_fstatat(int dfd, const char __user \*filename, struct kstat \*stat,/i\#ifdef CONFIG_KSU\nextern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);\n#endif\n' fs/stat.c
            sed -i '/if ((flag & ~(AT_SYMLINK_NOFOLLOW | AT_NO_AUTOMOUNT |/i\	#ifdef CONFIG_KSU\n	ksu_handle_stat(&dfd, &filename, &flag);\n	#endif\n' fs/stat.c
        fi
        ;;

    # drivers/input changes
    ## input.c
    drivers/input/input.c)
        sed -i '/static void input_handle_event/i\#ifdef CONFIG_KSU\nextern bool ksu_input_hook __read_mostly;\nextern int ksu_handle_input_handle_event(unsigned int *type, unsigned int *code, int *value);\n#endif\n' drivers/input/input.c
        sed -i '/int disposition = input_get_disposition(dev, type, code, &value);/a\	#ifdef CONFIG_KSU\n	if (unlikely(ksu_input_hook))\n		ksu_handle_input_handle_event(&type, &code, &value);\n	#endif' drivers/input/input.c
        ;;
    esac

done
sed -i '/-warn-stack-size/d' Makefile

echo "-android12-9-g62ff7270b368-ab1905" > localversion


python3 - <<'PYEOF'
p = 'kernel/module.c'
s = open(p).read()
if 'bypass module CRC' not in s:
    marker = 'static int check_version(const struct load_info *info,'
    i = s.index(marker)
    k = s.index('if (!crc)', i)
    s = s[:k] + 'return 1; /* bypass module CRC */\n\t' + s[k:]
    s = s.replace('} else if (!same_magic(modmagic, vermagic, info->index.vers)) {', '} else if (0) { /* vermagic bypass */')
    open(p, 'w').write(s)
    print('module.c patched: CRC + vermagic bypass')
PYEOF
cat > kernel/cfi_stub.c << 'STUBEOF'
/* CFI/UBSAN stubs - stock modules are CFI-built; provide the runtime symbols */
#include <linux/module.h>
#include <linux/kernel.h>

void __ubsan_handle_cfi_check_fail_abort(void *data, void *ptr, void *vtable)
{
	panic("CFI check failed (stub handler) ptr=%p", ptr);
}
EXPORT_SYMBOL_GPL(__ubsan_handle_cfi_check_fail_abort);

void __ubsan_handle_cfi_check_fail(void *data, void *ptr, void *vtable)
{
	pr_warn("CFI check failed (stub, permissive) ptr=%p\n", ptr);
}
EXPORT_SYMBOL_GPL(__ubsan_handle_cfi_check_fail);

void __cfi_slowpath(unsigned long long id, void *ptr, void *diag) { }
EXPORT_SYMBOL_GPL(__cfi_slowpath);

void __cfi_slowpath_diag(unsigned long long id, void *ptr, void *diag) { }
EXPORT_SYMBOL_GPL(__cfi_slowpath_diag);
STUBEOF
grep -q cfi_stub kernel/Makefile || echo 'obj-y += cfi_stub.o' >> kernel/Makefile
python3 - <<'PYEOF'
p = 'kernel/module.c'
s = open(p).read()
if 'allow duplicate exports' not in s:
    marker = 'static int verify_exported_symbols(struct module *mod)'
    i = s.index(marker)
    k = s.index('for (i = 0; i < ARRAY_SIZE(arr); i++)', i)
    s = s[:k] + 'return 0; /* allow duplicate exports */\n\t' + s[k:]
    open(p, 'w').write(s)
    print('module.c patched: duplicate export bypass')
PYEOF
python3 - <<'PYEOF'
p = 'drivers/soc/sprd/debug/hang_debug/sprd_wdh.c'
s = open(p).read()
if 'notifier disabled' not in s:
    i = s.index('sprd_module_notifier_fn(struct notifier_block *nb,')
    k = s.index('if (action != MODULE_STATE_LIVE)', i)
    s = s[:k] + 'return NOTIFY_DONE; /* notifier disabled */\n\t' + s[k:]
    open(p, 'w').write(s)
    print('sprd_wdh.c patched: module notifier disabled')
PYEOF
python3 - <<'PYEOF'
p = 'arch/arm64/Kconfig'
s = open(p).read()
if 'PREL32 disabled' not in s and 'select HAVE_ARCH_PREL32_RELOCATIONS' in s:
    s = s.replace('select HAVE_ARCH_PREL32_RELOCATIONS', '# PREL32 disabled - match stock module ksymtab format\n\t# select HAVE_ARCH_PREL32_RELOCATIONS')
    open(p, 'w').write(s)
    print('arch/arm64/Kconfig patched: PREL32 disabled')
PYEOF
cat > kernel/dbg_fdt.c << 'DBGEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/of_platform.h>

static int __init dbg_fdt(void)
{
	struct device_node *np;
	const char *st;
	int cnt = 0;
	pr_err("DBGFDT: ===== FDT WALK =====\n");
	for_each_available_node(np) {
		cnt++;
		if (strstr(np->full_name, "201d") || strstr(np->full_name, "sdio") || strstr(np->full_name, "mmc")) {
			st = of_get_property(np, "status", NULL);
			pr_err("DBGFDT: node=%s status=%s\n", np->full_name, st ? st : "(none)");
		}
	}
	pr_err("DBGFDT: total nodes=%d\n", cnt);
	np = of_find_node_by_name(NULL, "201d0000.sdio");
	pr_err("DBGFDT: find_by_name sdio=%p\n", np);
	return 0;
}
late_initcall(dbg_fdt);
DBGEOF
grep -q dbg_fdt kernel/Makefile || echo 'obj-y += dbg_fdt.o' >> kernel/Makefile

python3 - <<'PYEOF'
p = 'kernel/dbg_fdt.c'
s = open(p).read()
s = s.replace('for_each_available_node(np) {', 'np = NULL;\n\twhile ((np = of_find_all_nodes(np))) {')
open(p, 'w').write(s)
print('dbg_fdt.c fixed: of_find_all_nodes walk')
PYEOF

cat > kernel/dbg_fdt.c << 'DBGEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>

static int __init dbg_fdt(void)
{
	struct device_node *np;
	struct platform_device *pdev;
	const char *st, *cmp;
	int cnt = 0;
	pr_err("DBGFDT: ===== FDT WALK v2 =====\n");
	np = NULL;
	while ((np = of_find_all_nodes(np))) {
		cnt++;
		if (strstr(np->full_name, "sdio")) {
			st = of_get_property(np, "status", NULL);
			cmp = of_get_property(np, "compatible", NULL);
			pdev = of_find_device_by_node(np);
			pr_err("DBGFDT: node=%s status=%s compat=%s pdev=%p\n",
				np->full_name, st ? st : "(none)", cmp ? cmp : "(none)", pdev);
		}
	}
	pr_err("DBGFDT: total nodes=%d\n", cnt);
	return 0;
}
late_initcall(dbg_fdt);
DBGEOF

cat > kernel/dbg_fdt.c << 'DBGEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/workqueue.h>

static struct delayed_work dbg_work;

static void dbg_late(struct work_struct *work)
{
	struct device *dev;
	struct device_driver *drv;
	int ret;
	pr_err("DBGFDT2: ===== LATE CHECK =====\n");
	dev = bus_find_device_by_name(&platform_bus_type, NULL, "201d0000.sdio");
	pr_err("DBGFDT2: pdev=%p bound=%s\n", dev,
		(dev && dev->driver) ? dev->driver->name : "(none)");
	drv = driver_find("sdhci_sprd_r11", &platform_bus_type);
	pr_err("DBGFDT2: driver found=%p\n", drv);
	if (dev && !dev->driver) {
		ret = device_attach(dev);
		pr_err("DBGFDT2: manual device_attach ret=%d bound=%s\n", ret,
			(dev && dev->driver) ? dev->driver->name : "(none)");
	}
}

static int __init dbg_fdt(void)
{
	INIT_DELAYED_WORK(&dbg_work, dbg_late);
	schedule_delayed_work(&dbg_work, msecs_to_jiffies(5000));
	pr_err("DBGFDT: probe scheduled\n");
	return 0;
}
late_initcall(dbg_fdt);
DBGEOF

cat > kernel/dbg_fdt.c << 'DBGEOF'
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/device.h>
#include <linux/delay.h>
#include <linux/workqueue.h>

static struct delayed_work dbg_work;

static int drv_cb(struct device_driver *drv, void *data)
{
	int *cnt = data;
	(*cnt)++;
	if (strstr(drv->name, "sprd") || strstr(drv->name, "sdhci") || strstr(drv->name, "gpio"))
		pr_err("DBGFDT3: drv on bus: %s\n", drv->name);
	return 0;
}

static void dbg_late(struct work_struct *work)
{
	struct module *mod;
	int cnt = 0;
	pr_err("DBGFDT3: ===== DRIVER/MOD CHECK =====\n");
	bus_for_each_drv(&platform_bus_type, NULL, &cnt, drv_cb);
	pr_err("DBGFDT3: platform drivers total=%d\n", cnt);
	mod = find_module("sdhci_sprd");
	pr_err("DBGFDT3: mod=%p init_ptr=%p state=%d\n",
		mod, mod ? mod->init : NULL, mod ? (int)mod->state : -1);
	mod = find_module("gpio_sprd");
	pr_err("DBGFDT3: gpio mod=%p init_ptr=%p state=%d\n",
		mod, mod ? mod->init : NULL, mod ? (int)mod->state : -1);
}

static int __init dbg_fdt(void)
{
	INIT_DELAYED_WORK(&dbg_work, dbg_late);
	schedule_delayed_work(&dbg_work, msecs_to_jiffies(5000));
	pr_err("DBGFDT: v3 scheduled\n");
	return 0;
}
late_initcall(dbg_fdt);
DBGEOF
