![Flight505 Marketplace](./marketplace-hero.jpg)

# flight505 Plugin Marketplace

**Official Claude Code plugin marketplace by Jesper Vang**

This marketplace provides a centralized source for installing all flight505 plugins with a single command.

## 🎯 Available Plugins

### 1. 🚀 SDK Bridge
**SOTA autonomous development with intelligent generative UI** ⭐ NEW v2.0

**Generative UI Features (v2.0)**:
- Interactive onboarding with AskUserQuestion (model, parallel, features)
- Live progress updates with TodoWrite polling (simulated real-time)
- Proactive completion notifications (SessionStart hook with LLM analysis)
- Context-aware help (UserPromptSubmit hook for natural questions)
- Comprehensive reports with ✅/❌ file validation

**Core Autonomous Features**:
- Autonomous multi-session development with hybrid loops
- Semantic memory (cross-project learning)
- Adaptive model selection (Sonnet/Opus routing)
- Parallel execution (2-4x speedup, git-isolated workers)
- Human-in-the-loop approval workflow

**Version**: 2.0.0 (Jan 2026)
**Repository**: [sdk-bridge-marketplace](https://github.com/flight505/sdk-bridge-marketplace)
**Documentation**: [README](https://github.com/flight505/sdk-bridge-marketplace#readme) | [Installation Guide](https://github.com/flight505/sdk-bridge-marketplace/blob/main/INSTALLATION.md)

### 2. 🎨 Storybook Assistant
**SOTA 2026 Storybook development toolkit**

- Vision AI design-to-code transformation
- Natural language component generation
- AI-powered accessibility remediation (WCAG 2.2)
- React 19 & Next.js 15 Server Components
- Dark mode auto-generation
- Performance analysis
- CI/CD pipeline generator

**Repository**: [storybook-assistant-plugin](https://github.com/flight505/storybook-assistant-plugin)
**Documentation**: [README](https://github.com/flight505/storybook-assistant-plugin#readme)

### 3. 📋 Claude Project Planner
**AI-powered project planning assistant**

- Project breakdown and task management
- Timeline estimation
- Progress tracking
- Sprint planning
- Resource allocation

**Repository**: [claude-project-planner](https://github.com/flight505/claude-project-planner)
**Documentation**: [README](https://github.com/flight505/claude-project-planner#readme)

### 4. 🍌 Nano Banana
**AI image and diagram generation**

- State-of-the-art image generation (Gemini 3 Pro, FLUX)
- Technical diagram creation with quality review
- Mermaid diagram support
- Smart iteration and optimization
- Powered by OpenRouter

**Repository**: [nano-banana](https://github.com/flight505/nano-banana)
**Documentation**: [README](https://github.com/flight505/nano-banana#readme)

---

## 🚀 Installation

### Method 1: Install Entire Marketplace (All Plugins)

```bash
claude

# In Claude prompt:
/plugin marketplace add flight505/flight505-marketplace

# Install all plugins:
/plugin install storybook-assistant@flight505-marketplace
/plugin install claude-project-planner@flight505-marketplace
/plugin install nano-banana@flight505-marketplace
/plugin install sdk-bridge@flight505-marketplace
```

This installs **all 4 plugins**.

### Method 2: Install Individual Plugins

```bash
claude

# Add marketplace first:
/plugin marketplace add flight505/flight505-marketplace

# Then install specific plugin:
/plugin install sdk-bridge@flight505-marketplace
/plugin install storybook-assistant@flight505-marketplace
/plugin install claude-project-planner@flight505-marketplace
/plugin install nano-banana@flight505-marketplace
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

- ✅ **sdk-bridge** - Autonomous development with hybrid loops and parallel execution
- ✅ **storybook-assistant** - Full Storybook 9 development toolkit
- ✅ **claude-project-planner** - Project management assistant
- ✅ **nano-banana** - Image and diagram generation

All plugins are maintained and updated regularly.

---

## 🔄 Updating Plugins

Plugins installed via marketplace can be updated:

```bash
claude

/plugin update sdk-bridge@flight505-marketplace
/plugin update storybook-assistant@flight505-marketplace
/plugin update claude-project-planner@flight505-marketplace
/plugin update nano-banana@flight505-marketplace
```

Or update the marketplace manually:

```bash
cd ~/.claude/plugins/marketplaces/flight505
git pull
```

---

## 📚 Documentation

Each plugin has comprehensive documentation:

- [SDK Bridge](https://github.com/flight505/sdk-bridge-marketplace#readme) - Quick Start | [Installation Guide](https://github.com/flight505/sdk-bridge-marketplace/blob/main/INSTALLATION.md) | Skill Guide
- [Storybook Assistant](https://github.com/flight505/storybook-assistant-plugin#readme) - Complete Storybook toolkit
- [Project Planner](https://github.com/flight505/claude-project-planner#readme) - Project planning & tracking
- [Nano Banana](https://github.com/flight505/nano-banana#readme) - Image & diagram generation

---

## 🆘 Support

- **Issues**: Report bugs at each plugin's GitHub repository
- **Discussions**: [GitHub Discussions](https://github.com/flight505/flight505-marketplace/discussions)
- **Author**: [Jesper Vang](https://github.com/flight505)

---

## 📄 License

Individual plugins may have different licenses. Check each repository:

- **sdk-bridge**: MIT License
- **storybook-assistant**: MIT License
- **claude-project-planner**: Check repository
- **nano-banana**: Check repository

---

## 🔗 Links

- **GitHub**: https://github.com/flight505/flight505-marketplace
- **Author**: [@flight505](https://github.com/flight505)
- **Plugin Repositories**:
  - [SDK Bridge](https://github.com/flight505/sdk-bridge-marketplace)
  - [Storybook Assistant](https://github.com/flight505/storybook-assistant-plugin)
  - [Claude Project Planner](https://github.com/flight505/claude-project-planner)
  - [Nano Banana](https://github.com/flight505/nano-banana)

---

**Built with ❤️ by Jesper Vang**

**Powered by Claude Code** 🚀
