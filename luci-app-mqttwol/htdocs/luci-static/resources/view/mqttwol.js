'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require tools.widgets as widgets';

return view.extend({
	load: function() {
		return uci.load('mqttwol');
	},

	render: function() {
		const m = new form.Map(
			'mqttwol',
			_('MQTT Wake-on-LAN'),
			_('MQTT subscription and Wake-on-LAN via mosquitto_sub and etherwake.')
		);

		const s = m.section(form.NamedSection, 'main', 'mqttwol', _('Settings'));

		let o;

		o = s.option(form.Flag, 'enabled', _('Enable'));

		o = s.option(form.Value, 'server', _('MQTT broker address'));
		o.rmempty = false;
		o.datatype = 'host';

		o = s.option(form.Value, 'port', _('MQTT broker port'));
		o.placeholder = '1883';
		o.datatype = 'port';
		o.rmempty = false;

		o = s.option(form.Flag, 'use_auth', _('MQTT use authentication'));
		o.default = o.disabled;

		o = s.option(form.Value, 'username', _('MQTT username'));
		o.depends('use_auth', '1');
		o.datatype = 'string';
		o.optional = true;

		o = s.option(form.Value, 'password', _('MQTT password'));
		o.password = true;
		o.depends('use_auth', '1');
		o.datatype = 'string';
		o.optional = true;

		o = s.option(form.Value, 'topic', _('MQTT topic'));
		o.rmempty = false;
		o.datatype = 'string';

		o = s.option(
			widgets.DeviceSelect,
			'interface',
			_('Ethernet interfaces'),
			_('Network devices for etherwake (same control as on the interfaces page). Choose one or more; each gets a magic packet.')
		);
		o.multiple = true;
		o.rmempty = false;

		const origSave = m.save.bind(m);
		m.save = function(cb, silent) {
			function beforeSave(/* ... */) {
				if (uci.get('mqttwol', 'main', 'use_auth') != '1') {
					uci.unset('mqttwol', 'main', 'username');
					uci.unset('mqttwol', 'main', 'password');
				}
				const args = arguments;
				return (typeof cb == 'function')
					? cb.apply(null, args)
					: undefined;
			}

			return origSave(beforeSave, silent).then(function() {
				return fs.exec_direct('/etc/init.d/mqttwol', [ 'restart' ]);
			});
		};

		return m.render();
	},
});
