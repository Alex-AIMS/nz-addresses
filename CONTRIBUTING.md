# Contributing to NZ Addresses

Thank you for your interest in contributing to NZ Addresses! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build something useful for the New Zealand developer community.

## Getting Started

### Prerequisites

- Docker and Docker Compose
- .NET 8.0 SDK (for local development)
- Git
- A LINZ API key (free from https://data.linz.govt.nz/)
- A Stats NZ API key (free from https://datafinder.stats.govt.nz/)

### Setting Up Your Development Environment

1. **Fork the repository** on GitHub

2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/nz-addresses.git
   cd nz-addresses
   ```

3. **Create your config.env:**
   ```bash
   cp config.env.example config.env
   # Edit config.env and add your API keys
   ```

4. **Build and run:**
   ```bash
   docker build -t nz-addresses:latest -f docker/Dockerfile .
   docker run -d --env-file config.env -p 5432:5432 -p 8080:8080 --name nz-addresses nz-addresses:latest
   ```

5. **Load data:**
   ```bash
   docker exec nz-addresses bash /home/appuser/scripts/download_data_fast.sh
   docker exec nz-addresses bash /home/appuser/scripts/load_hierarchy_correct.sh
   docker exec nz-addresses bash /home/appuser/scripts/etl_simple.sh
   ```

6. **Verify it works:**
   Open http://localhost:8080/swagger

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](../../issues)
2. If not, create a new issue with:
   - Clear, descriptive title
   - Steps to reproduce
   - Expected vs actual behavior
   - Your environment (OS, Docker version, .NET version)
   - Relevant logs or error messages

### Suggesting Features

1. Check [Issues](../../issues) for existing feature requests
2. Create a new issue with:
   - Clear description of the feature
   - Use case / problem it solves
   - Proposed implementation (if you have ideas)

### Submitting Pull Requests

1. **Create a branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes:**
   - Write clean, readable code
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed

3. **Test your changes:**
   - Ensure Docker builds successfully
   - Test API endpoints with Swagger
   - Verify database migrations work

4. **Commit with clear messages:**
   ```bash
   git commit -m "Add feature: description of what you did"
   ```

5. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

6. **Create a Pull Request:**
   - Describe what your PR does
   - Reference any related issues
   - Include before/after examples if applicable

## Code Style Guidelines

### C# (.NET)
- Follow standard C# naming conventions
- Use async/await for database operations
- Keep methods focused and single-purpose
- Add XML documentation for public APIs

### SQL
- Use lowercase for SQL keywords
- Indent subqueries
- Add comments for complex queries
- Use meaningful table/column aliases

### Bash Scripts
- Use `set -e` for error handling
- Add logging with timestamps
- Include usage instructions in comments
- Quote variables to handle spaces

### Python Scripts
- Follow PEP 8
- Use type hints where appropriate
- Add docstrings for functions
- Handle errors gracefully

## Project Structure

```
nz-addresses/
├── docker/              # Container configuration
│   ├── Dockerfile
│   └── initdb/         # Database schema and initialization
├── scripts/            # ETL and data management
├── src/                # .NET application
│   ├── NzAddresses.Domain/     # Entities and DTOs
│   ├── NzAddresses.Core/       # Business logic
│   └── NzAddresses.WebApi/     # REST API
├── docs/               # Documentation
└── data/              # Data files (git-ignored)
```

## Areas Needing Help

We'd love contributions in these areas:

- **Performance optimization** - Query optimization, caching strategies
- **Testing** - Unit tests, integration tests, load tests
- **Documentation** - API examples, architecture diagrams, video tutorials
- **Features** - Bulk address validation, address autocomplete, fuzzy matching improvements
- **DevOps** - CI/CD pipelines, automated testing, Docker optimizations
- **Data quality** - Handling edge cases, improving centroid accuracy

## Questions?

- Open a [Discussion](../../discussions) for general questions
- Create an [Issue](../../issues) for bugs or feature requests
- Check existing documentation in `/docs`

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

Thank you for contributing! 🇳🇿
