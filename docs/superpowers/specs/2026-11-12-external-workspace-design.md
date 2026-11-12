# Orivyn Desk: app-owned external display workspace

Request: a DeX-like workspace when iPhone connects by USB-C to HDMI, while inside Orivyn; embedded apps if possible. Public iOS APIs cannot host arbitrary installed apps inside another app. External app links switch applications. iPhone external display is not iPad extended desktop or an OS replacement.

Feasible first version: a real UIKit external-display scene with an Orivyn-only full-screen dashboard and a phone controller. Display app-owned conversation, files and projects using the same in-process AppModel. No second model/runtime, duplicate data store, new background privilege or automatic private-screen disclosure. Phone user explicitly enables Desk after display attachment, can choose a panel and turn it off to return to mirroring. No fabricated connected state or simulator-only HDMI claim.

Use the noninteractive external-window scene role, supported on deployment iOS26. A UIHostingController hosts the app-owned display view. Lifecycle must release window on disconnect/disable, handle reconnect and safe missing-model startup, and hide sensitive display on background/lock. Default is off; do not persist automatic activation. No iOS27-only scene accessory requirement.

Phone remains the controller and native input surface. First scope is readable app panels, not a universal app/window manager. Web browsing remains the actual Safari view on the phone until a separately tested external interaction design exists. A connected virtual computer is a separately authorized backend, not an implicit free service.

Required verification: pure connection/enable/panel/background lifecycle tests; actual native phone control UI with no display truthfully disconnected; scene configuration and window creation native compile checks; existing single-engine/conversation regressions. Physical USB-C/HDMI attach/reconnect, resolutions and lock behavior require compatible physical hardware. A simulator pass does not close that acceptance requirement.

Sources: Apple TN3187 scene lifecycle; UIKit Presenting content on a connected display; iPhone16Plus official technical specifications. Physical supported resolution depends on hardware/adapter/cable/display; never guarantee4K60 solely from an iPhone model name.
