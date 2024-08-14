# Contributing

Thanks for your interest in contributing to zabi! Please take a moment to review this document **before submitting a pull request.**

If you want to contribute, but aren't sure where to start, you can create a [new discussion](https://github.com/Raiden1411/zabi/discussions).

> **Note**
>
> **Please ask first before starting work on any significant new features.**
>
> It's never a fun experience to have your pull request declined after investing time and effort into a new feature. To avoid this from happening, we request that contributors create a [feature request](https://github.com/Raiden1411/zabi/discussions/new?category=ideas) to first discuss any API changes or significant new ideas.

<br>

## Basic guide

This guide is intended to help you get started with contributing. By following these steps, you will understand the development process and workflow.

1. [Cloning the repository](#cloning-the-repository)
2. [Installing zig](#installing-zig)
3. [Installing Foundry](#installing-foundry)
4. [Building Zabi](#building)
5. [Running the test suite](#running-the-test-suite)
6. [Writing documentation](#writing-documentation)
7. [Submitting a pull request](#submitting-a-pull-request)

---

### Cloning the repository

To start contributing to the project, clone it to your local machine using git:

```bash
git clone https://github.com/Raiden1411/zabi.git 
```

Or the [GitHub CLI](https://cli.github.com):

```bash
gh repo clone Raiden1411/zabi
```

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Installing Zig

You can install zig using any package manager from your distribution in case you are on linux. Otherwise you can download the binaries [here](https://ziglang.org/download/).

You can also use [zvm](https://www.zvm.app/) which is the recommended way of managing you zig version installs.

---

### Installing Foundry

Zabi uses [Foundry](https://book.getfoundry.sh/) for some testing (`zig build rpc_test` and `zig build wallet_test`). We run a local [Anvil](https://github.com/foundry-rs/foundry/tree/master/anvil) instance against a forked Ethereum node, where we can also use tools like [Forge](https://book.getfoundry.sh/forge/) to deploy test contracts to it.

Install Foundry using the following command:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Building

Once you have cloned the repo and have the correct version of zig running on your computer you can now run `zig build` to ensure that everything gets built properly.

Zabi supports `version 0.12.0` and `version 0.13.0` of zig in seperate branches. You can checkout each seperate branch and work in those branches if that is your goal.

---

### Running the test suite

You can also run `zig build test -freference-trace` to run our test suite to ensure that you don't have any issues running the tests.

When adding new features or fixing bugs, it's important to add test cases to cover the new/updated behavior.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Writing documentation

Documentation is crucial to helping developers of all experience levels use zabi. zabi uses [Vocs](https://vocs.dev) and Markdown for the documentation site (located at [`docs`](../docs)). To start the site in dev mode, run:

```bash
pnpm dev 
```

Try to keep documentation brief and use plain language so people of all experience levels can understand. If you think something is unclear or could be explained better, you are welcome to open a pull request.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

### Submitting a pull request

When you're ready to submit a pull request, you can follow these naming conventions:

- Pull request titles use the [Imperative Mood](https://en.wikipedia.org/wiki/Imperative_mood) (e.g., `Add something`, `Fix something`).

When you submit a pull request, GitHub will automatically lint, build, and test your changes. If you see an ❌, it's most likely a bug in your code. Please, inspect the logs through the GitHub UI to find the cause.

The CI might also fail sometimes when it comes to the test runner. If running doesn't fix the problem then it's most likely a bug in your code.

<div align="right">
  <a href="#basic-guide">&uarr; back to top</a></b>
</div>

---

<br>

<div>
  ✅ Now you're ready to contribute to zabi!
</div>

<div align="right">
  <a href="#advanced-guide">&uarr; back to top</a></b>
</div>

