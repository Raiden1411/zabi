import { defineConfig } from "vocs";
import { sidebar } from "./sidebar";

export default defineConfig({
	title: "Zabi",
	titleTemplate: "%s - Zabi",
	description:
		"Zig interface for interacting with ethereum and other EVM based chains",
	editLink: {
		pattern: "https://github.com/Raiden1411/zabi/edit/main/docs/pages/:path",
		text: "Suggest changes to this page",
	},
	rootDir: ".",
	sidebar,
	socials: [
		{
			icon: "github",
			link: "https://github.com/Raiden1411/zabi",
		},
		{
			icon: "x",
			link: "https://twitter.com/0xRaiden_",
		},
	],
	head: (
		<>
			<meta
				name="keywords"
				content="ethereum, abi, zig, evm, eip-712, web3, optimism"
			/>
			<meta property="og:url" content="https://zabi.sh/" />
			<meta property="twitter:image" content="https://zabi.sh/zabi.svg" />
			<meta name="twitter:card" content="summary_large_image" />
		</>
	),
	ogImageUrl: {
		"/": "/zabi.svg",
	},
	iconUrl: "/zabi.svg",
	logoUrl: {
		light: "/zabi.svg",
		dark: "/zabi.svg",
	},
	topNav: [
		{ text: "Init", link: "/" },
		{
			text: "v0.12.0",
			items: [
				{
					text: "Releases",
					link: "https://github.com/Raiden1411/zabi/releases",
				},
			],
		},
		{
			text: "Examples",
			link: "https://github.com/Raiden1411/zabi/tree/main/examples",
		},
	],
	sponsors: [
		{
			name: "Individuals",
			height: 60,
			items: [
				[
					{
						name: "awkweb",
						link: "https://github.com/tmm",
						image: "https://avatars.githubusercontent.com/u/6759464?v=4",
					},
				],
				[
					{
						name: "merkleplant",
						link: "https://github.com/pmerkleplant",
						image: "https://avatars.githubusercontent.com/u/85061506?v=4",
					},
				],
			],
		},
	],
});
