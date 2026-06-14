<script lang="ts">
	import './layout.css';
	import favicon from '$lib/assets/favicon.svg';

	let { children } = $props();

	const siteSchema = {
		"@context": "https://schema.org",
		"@type": "WebSite",
		"name": "Encorr",
		"url": "https://encorr.app"
	};

	const orgSchema = {
		"@context": "https://schema.org",
		"@type": "Organization",
		"name": "Encorr",
		"url": "https://encorr.app",
		"logo": "https://encorr.app/og/encorr-social.png",
		"sameAs": ["https://github.com/encorr-app/encorr"]
	};
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	{@html `<script type="application/ld+json">${JSON.stringify(siteSchema)}</script>`}
	{@html `<script type="application/ld+json">${JSON.stringify(orgSchema)}</script>`}
</svelte:head>
{@render children()}
