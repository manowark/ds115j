// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Module-capable variant of drivers/power/reset/qnap-poweroff.c.
 *
 * The in-tree driver is bool-only. This version uses the exported sys-off
 * handler API so Debian's stock armmp kernel can load it as an external module.
 */

#include <linux/clk.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/reboot.h>
#include <linux/serial_reg.h>

struct power_off_cfg {
	u32 baud;
	char cmd;
};

struct qnap_poweroff {
	void __iomem *base;
	unsigned long tclk;
	const struct power_off_cfg *cfg;
};

#define UART1_REG(poweroff, reg) \
	((poweroff)->base + ((UART_##reg) << 2))

static const struct power_off_cfg qnap_power_off_cfg = {
	.baud = 19200,
	.cmd = 'A',
};

static const struct power_off_cfg synology_power_off_cfg = {
	.baud = 9600,
	.cmd = '1',
};

static int qnap_power_off(struct sys_off_data *data)
{
	struct qnap_poweroff *poweroff = data->cb_data;
	const unsigned int divisor =
		(poweroff->tclk + (8 * poweroff->cfg->baud)) /
		(16 * poweroff->cfg->baud);

	pr_emerg("qnap_poweroff: triggering power-off\n");

	writel(0x83, UART1_REG(poweroff, LCR));
	writel(divisor & 0xff, UART1_REG(poweroff, DLL));
	writel((divisor >> 8) & 0xff, UART1_REG(poweroff, DLM));
	writel(0x03, UART1_REG(poweroff, LCR));
	writel(0x00, UART1_REG(poweroff, IER));
	writel(0x00, UART1_REG(poweroff, FCR));
	writel(0x00, UART1_REG(poweroff, MCR));
	writel(poweroff->cfg->cmd, UART1_REG(poweroff, TX));

	return NOTIFY_DONE;
}

static int qnap_power_off_probe(struct platform_device *pdev)
{
	struct qnap_poweroff *poweroff;
	struct resource *res;
	struct clk *clk;

	poweroff = devm_kzalloc(&pdev->dev, sizeof(*poweroff), GFP_KERNEL);
	if (!poweroff)
		return -ENOMEM;

	poweroff->cfg = device_get_match_data(&pdev->dev);
	if (!poweroff->cfg)
		return -EINVAL;

	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res)
		return -EINVAL;

	/*
	 * Match the in-tree driver: UART1 and this platform device intentionally
	 * overlap because the power-off handler takes over UART1 only at shutdown.
	 */
	poweroff->base = devm_ioremap(&pdev->dev, res->start,
				     resource_size(res));
	if (!poweroff->base)
		return -ENOMEM;

	clk = devm_clk_get(&pdev->dev, NULL);
	if (IS_ERR(clk))
		return dev_err_probe(&pdev->dev, PTR_ERR(clk),
				     "failed to get UART clock\n");

	poweroff->tclk = clk_get_rate(clk);

	return devm_register_power_off_handler(&pdev->dev, qnap_power_off,
					       poweroff);
}

static const struct of_device_id qnap_power_off_of_match[] = {
	{
		.compatible = "qnap,power-off",
		.data = &qnap_power_off_cfg,
	},
	{
		.compatible = "synology,power-off",
		.data = &synology_power_off_cfg,
	},
	{}
};

static struct platform_driver qnap_power_off_driver = {
	.probe = qnap_power_off_probe,
	.driver = {
		.name = "qnap_poweroff",
		.of_match_table = qnap_power_off_of_match,
	},
};
module_platform_driver(qnap_power_off_driver);

MODULE_AUTHOR("Andrew Lunn; DS115j module adaptation");
MODULE_DESCRIPTION("QNAP/Synology UART power-off driver");
MODULE_LICENSE("GPL");
