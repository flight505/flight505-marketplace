# flight505 Plugin Marketplace

**Official Claude Code plugin marketplace by Jesper Vang**

This marketplace provides a centralized source for installing all flight505 plugins with a single command.

## 🎯 Available Plugins

### 1. 🎨 Storybook Assistant
**SOTA 2026 Storybook development toolkit**

- Vision AI design-to-code transformation
- Natural language component generation
- AI-powered accessibility remediation (WCAG 2.2)
- React 19 & Next.js 15 Server Components
- Dark mode auto-generation
- Performance analysis
- CI/CD pipeline generator

**Repository**: [storybook-assistant-plugin](https://github.com/flight505/storybook-assistant-plugin)

### 2. 📋 Claude Project Planner
**AI-powered project planning assistant**

- Project breakdown and task management
- Timeline estimation
- Progress tracking
- Sprint planning
- Resource allocation

**Repository**: [claude-project-planner](https://github.com/flight505/claude-project-planner)

### 3. 🍌 Nano Banana
**AI image and diagram generation**

- State-of-the-art image generation (Gemini 3 Pro, FLUX)
- Technical diagram creation with quality review
- Mermaid diagram support
- Smart iteration and optimization
- Powered by OpenRouter

**Repository**: [nano-banana](https://github.com/flight505/nano-banana)

---

## 🚀 Installation

### Method 1: Install Entire Marketplace (All Plugins)

```bash
claude

# In Claude prompt:
/plugin

# When prompted, enter:
flight505/flight505-marketplace
```

This installs **all 3 plugins** at once.

### Method 2: Install Individual Plugins

```bash
claude

/plugin

# Choose one:
flight505/storybook-assistant-plugin
flight505/claude-project-planner
flight505/nano-banana
```

### Method 3: Manual Installation

```bash
# Clone the marketplace
git clone https://github.com/flight505/flight505-marketplace.git ~/.claude/plugins/marketplaces/flight505

# Claude Code will auto-discover and install all plugins
claude
```

---

## 📦 What Gets Installed

When you install this marketplace, you get:

- ✅ **storybook-assistant** - Full Storybook 9 development toolkit
- ✅ **claude-project-planner** - Project management assistant
- ✅ **nano-banana** - Image and diagram generation

All plugins are maintained and updated regularly.

---

## 🔄 Updating Plugins

Plugins installed via marketplace auto-update when marketplace refreshes:

```bash
claude

/plugin update
```

Or update the marketplace manually:

```bash
cd ~/.claude/plugins/marketplaces/flight505
git pull
```

---

## 📚 Documentation

Each plugin has comprehensive documentation:

- [Storybook Assistant Docs](https://github.com/flight505/storybook-assistant-plugin#readme)
- [Project Planner Docs](https://github.com/flight505/claude-project-planner#readme)
- [Nano Banana Docs](https://github.com/flight505/nano-banana#readme)

---

## 🆘 Support

- **Issues**: Report bugs at each plugin's GitHub repository
- **Discussions**: [GitHub Discussions](https://github.com/flight505/flight505-marketplace/discussions)
- **Author**: [Jesper Vang](https://github.com/flight505)

---

## 📄 License

Individual plugins may have different licenses. Check each repository:

- **storybook-assistant**: MIT License
- **claude-project-planner**: Check repository
- **nano-banana**: Check repository

---

## 🔗 Links

- **GitHub**: https://github.com/flight505/flight505-marketplace
- **Author**: [@flight505](https://github.com/flight505)

---

**Built with ❤️ by Jesper Vang**

**Powered by Claude Code** 🚀
