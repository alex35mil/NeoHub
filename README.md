<h1 align="center">NeoHub</h1>

<p align="center">
    <img width="600" alt="NeoHub" src="https://user-images.githubusercontent.com/4244251/281020657-ab8ceed5-8b4e-4366-89e0-4640b1887c2c.png">
</p>

## Why?
[Neovide](https://neovide.dev/) is a sweeeeet GUI for [Neovim](https://neovim.io/), but I had two annoying issues.
1. When multiple instances are running, it is hard to switch between them as each instance is a separate macOS process, and all the processes are named `neovide` in the `⌘ ⇥` list.
2. Often, I accidentally run a project that is already running, resulting in a Neovim error related to existing swap files.

## Features
So, what NeoHub offers?
1. Global hotkey that shows a switcher between Neovide instances. You can hit this hotkey from anywhere and activate a project you need.
2. CLI, which executes new Neovide instances, and if an instance at the current path is already running, it activates it instead of spawning a new one.

## Requirements
- `macOS 13+`.
- Administrative privileges to install the CLI.
- `neovide` available in your `PATH`.

## Download
Get it from the [Releases](https://github.com/alex35mil/NeoHub/releases).

## Installation
This a macOS app. Unzip the `NeoHub.zip` and move `NeoHub.app` to the `Applications` folder.

On the very first launch, you will be asked to install the CLI. You will need to enter an administrative password. 

## Usage
### CLI
Once installed, the `neohub` command should become available in your shell. This is the only way to launch a Neovide through the NeoHub, so use `neohub` instead of `neovide` to launch editors. Otherwise, things won't work.

See `neovide --help` for available options.

### App
Hit `⌘ ⌃ N` (`Command + Control + N`) to open the switcher. The hotkey is configurable.

When in the switcher, you can quit all editors at once by pressing `⌘ Q`, or just a selected one with `⌘ ⌫`.

P.S. When you press the hotkey and there is only one Neovide instance is running, NeoHub will activate it instead of showing the switcher.

## Credits
App icon is by [u/danbee](https://www.reddit.com/user/danbee/).

## License
MIT.
