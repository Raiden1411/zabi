import { defineConfig } from "vocs";
import { sidebar } from "./sidebar";

export default defineConfig({
	title: "Zabi",
	titleTemplate: "%s - Zabi",
	description:
		"Zig interface for interacting with ethereum and other EVM based chains",
	editLink: {
		pattern: "",
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
			<script
				src="https://cdn.usefathom.com/script.js"
				data-site="BYCJMNBD"
				defer
			/>
		</>
	),
	ogImageUrl: {
		"/": "/zabi.svg",
	},
	logoUrl: {
		light: "/zabi.svg",
		dark: "/zabi.svg",
	},
	topNav: [
		{ text: "Init", link: "/" },
		{
			text: "v0.4",
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
});
