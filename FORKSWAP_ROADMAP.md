# ForkSwap - Product Roadmap
## Current Status & Next Steps
**Last Updated**: 2025-10-14 05:00 UTC

---

## Current Status: v2.0.0 ✅

### What's Complete & Working
- ✅ **Web UI (v2.0.0)** - Production ready
  - Beautiful gradient UI (purple theme)
  - Fork listing with branch/size info
  - One-click fork switching
  - Fork deletion (with safety checks)
  - Real-time auto-refresh (5s intervals)
  - Mobile-responsive design
  - Favicon support
  - Real user confirmed using it! (IP 192.168.1.224)

- ✅ **Backend Overlay System**
  - Overlay deployment to target forks
  - OPENPILOT_DIR override (fixed in P0-1)
  - Firmware daemon protection (fixed in P0-2)
  - Automatic rollback on failures
  - Phase 4 progress indicators
  - Asset building & hashing

- ✅ **CLI Management**
  - `forkswap.sh` script
  - Fork switching via command line
  - Interactive menu
  - Automatic GitHub fork detection

### Critical Bugs Fixed
- ✅ **P0-1**: OPENPILOT_DIR override (needs `sudo -E`)
- ✅ **P0-2**: Phase 6 firmware daemon control (uses pgrep/kill)

### Test Results
- **Web UI**: 9/9 tests passed (100%)
- **Overall**: 0 critical bugs remaining
- **Production Ready**: YES ✅

---

## Phase 1: Core Features (v2.1) 🎯 NEXT

### Priority: HIGH

#### 1. Add New Fork from Web UI
**Status**: Not started
**Complexity**: Medium
**Time Estimate**: 2-3 hours

**Features**:
- GitHub URL input field
- Branch selection (optional)
- Auto-generate fork name from URL
- Progress bar during clone
- Submodule support (`--recurse-submodules`)
- Validation (check if fork already exists)

**Implementation**:
```python
@app.route('/api/clone', methods=['POST'])
def api_clone():
    """Clone a new fork from GitHub"""
    url = request.json.get('github_url')
    branch = request.json.get('branch', 'master')
    fork_name = generate_fork_name(url, branch)

    # Clone with progress tracking
    subprocess.run([
        'git', 'clone', '-b', branch,
        '--recurse-submodules',
        url, f'/data/forks/{fork_name}/openpilot'
    ])
```

**UI Changes**:
- Make "+ Add New Fork" button functional
- Modal dialog for URL/branch input
- Progress indicator during clone
- Success/error feedback

---

#### 2. Auto-Start Web UI on Boot
**Status**: Not started
**Complexity**: Low
**Time Estimate**: 30 minutes

**Approach**: Add to `system/manager/process_config.py`

**Implementation**:
```python
PythonProcess("forkswap_webui", "selfdrive.forkswap.webui", enabled=True, onroad=False, offroad=True),
```

**Benefits**:
- No manual start required
- Web UI available immediately after boot
- Survives reboots

**Testing**:
- Verify starts on boot
- Check logs for errors
- Confirm port 8080 accessible

---

#### 3. View Fork Details
**Status**: Not started
**Complexity**: Low
**Time Estimate**: 1 hour

**Features**:
- Latest commit hash
- Commit date
- Commit author
- Commit message
- Number of commits ahead/behind remote

**Implementation**:
```python
# In api_forks()
commit_info = subprocess.run(
    ['git', '-C', str(openpilot_path), 'log', '-1', '--format=%H|%an|%ae|%s|%cd'],
    capture_output=True, text=True
)
```

**UI Changes**:
- Expand fork card to show details
- "View Details" button
- Collapsible sections

---

#### 4. Disk Space Monitoring
**Status**: Not started
**Complexity**: Low
**Time Estimate**: 30 minutes

**Features**:
- Show available disk space
- Show space used by forks
- Warning when <2GB free
- Recommend deletion if low space

**Implementation**:
```python
@app.route('/api/disk')
def api_disk():
    result = subprocess.run(['df', '-h', '/data'], capture_output=True, text=True)
    return jsonify({
        'total': '64G',
        'used': '45G',
        'available': '19G',
        'percent': '70%'
    })
```

**UI Changes**:
- Disk space indicator in status card
- Color-coded (green/yellow/red)
- Show in fork list

---

## Phase 2: UX Enhancements (v2.2)

### Priority: MEDIUM

#### 5. Dark/Light Theme Toggle
**Time Estimate**: 2 hours

**Features**:
- Theme switcher button
- Persist preference (localStorage)
- Smooth transitions

**Implementation**:
```css
[data-theme="dark"] {
    --bg-gradient: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    --card-bg: #0f3460;
    --text-color: #e4e4e4;
}
```

---

#### 6. Fork Search/Filter
**Time Estimate**: 1 hour

**Features**:
- Search by fork name
- Filter by branch
- Sort by size/date/name

---

#### 7. Fork Switch History
**Time Estimate**: 2 hours

**Features**:
- Track last 10 switches
- Show timestamp
- Quick switch to recent forks

**Implementation**:
```python
# Store in /data/forkswap/history.json
{
    "history": [
        {"fork": "james5294-FrogPilot", "timestamp": 1697234567, "from": "james5294"},
        {"fork": "james5294", "timestamp": 1697234321, "from": "james5294-FrogPilot"}
    ]
}
```

---

#### 8. Branch Switching Within Fork
**Time Estimate**: 2-3 hours

**Features**:
- List branches in fork
- Switch branch without reboot
- Pull latest changes
- Stash/discard local changes

**Implementation**:
```python
@app.route('/api/branch', methods=['POST'])
def api_branch():
    fork_name = request.json.get('fork_name')
    branch = request.json.get('branch')
    subprocess.run(['git', '-C', fork_path, 'checkout', branch])
```

---

## Phase 3: Advanced Features (v2.3)

### Priority: LOW

#### 9. Update Fork from Remote
**Time Estimate**: 2 hours

**Features**:
- "Update Fork" button
- Pull latest changes from GitHub
- Show commits behind remote
- Automatic merge/rebase option

---

#### 10. Fork Comparison
**Time Estimate**: 3 hours

**Features**:
- Compare two forks
- Show commit differences
- Show file differences
- Highlight conflicts

---

#### 11. Backup/Restore Forks
**Time Estimate**: 3 hours

**Features**:
- Create fork backup (tar.gz)
- Restore from backup
- Upload backup to cloud
- Download backup

---

#### 12. Optional Password Protection
**Time Estimate**: 1 hour

**Features**:
- Basic auth username/password
- Set via environment variable
- Optional (disabled by default)

**Implementation**:
```python
from flask_httpauth import HTTPBasicAuth
auth = HTTPBasicAuth()

@auth.verify_password
def verify(username, password):
    return username == os.getenv('WEBUI_USER') and password == os.getenv('WEBUI_PASS')

@app.route('/')
@auth.login_required
def index():
    ...
```

---

#### 13. Fork Templates
**Time Estimate**: 2 hours

**Features**:
- Save fork configuration
- Quick clone from template
- Preset branches/settings

---

#### 14. Multi-Device Sync
**Time Estimate**: 4+ hours

**Features**:
- Sync fork list across devices
- Cloud storage integration
- Share fork configs

---

## Phase 4: Performance & Reliability (v2.4)

### Priority: MEDIUM

#### 15. Clone Progress Tracking
**Time Estimate**: 2 hours

**Features**:
- Real-time clone progress
- Estimated time remaining
- Cancel clone operation
- Resume interrupted clones

**Implementation**:
- Use `git clone` with `--progress`
- Parse progress output
- Stream to WebSocket
- Update UI in real-time

---

#### 16. Error Handling Improvements
**Time Estimate**: 2 hours

**Features**:
- Better error messages
- Actionable recommendations
- Automatic retry on network errors
- Rollback on failure

---

#### 17. Rate Limiting
**Time Estimate**: 1 hour

**Features**:
- Limit API requests per IP
- Prevent abuse
- Configurable limits

**Implementation**:
```python
from flask_limiter import Limiter
limiter = Limiter(app, key_func=get_remote_address)

@app.route('/api/delete', methods=['POST'])
@limiter.limit("5 per minute")
def api_delete():
    ...
```

---

#### 18. Logging Enhancements
**Time Estimate**: 1 hour

**Features**:
- Structured logging (JSON)
- Log rotation
- Log viewer in Web UI
- Export logs

---

## Phase 5: Integration (v3.0)

### Priority: LOW

#### 19. WebSocket Support
**Time Estimate**: 3 hours

**Features**:
- Real-time updates (no polling)
- Instant fork list refresh
- Live clone progress
- Push notifications

**Implementation**:
```python
from flask_socketio import SocketIO
socketio = SocketIO(app)

@socketio.on('connect')
def handle_connect():
    emit('fork_update', get_forks())
```

---

#### 20. Mobile App (React Native/Flutter)
**Time Estimate**: 2-3 weeks

**Features**:
- Native iOS/Android app
- Push notifications
- Offline support
- Better performance

---

#### 21. Desktop App (Electron)
**Time Estimate**: 1-2 weeks

**Features**:
- Native Windows/Mac/Linux app
- System tray integration
- Auto-discovery of devices
- Multi-device management

---

## Phase 6: Community Features (v3.1)

### Priority: FUTURE

#### 22. Fork Marketplace
**Time Estimate**: TBD

**Features**:
- Browse popular forks
- Rate/review forks
- One-click install
- Update notifications

---

#### 23. Fork Analytics
**Time Estimate**: TBD

**Features**:
- Track fork usage
- Performance metrics
- Crash reporting
- Feature usage

---

#### 24. Social Features
**Time Estimate**: TBD

**Features**:
- Share fork configs
- Follow users
- Discover forks
- Fork recommendations

---

## Technical Debt & Maintenance

### Ongoing Tasks

#### 25. Code Refactoring
- Extract API routes to separate files
- Create reusable components
- Add type hints (Python 3.8+)
- Improve code organization

---

#### 26. Testing
- Unit tests for API endpoints
- Integration tests for fork operations
- E2E tests for Web UI
- Performance benchmarks

---

#### 27. Documentation
- API documentation (OpenAPI/Swagger)
- User guide improvements
- Video tutorials
- FAQ expansion

---

#### 28. Security Audits
- Penetration testing
- Code review
- Dependency updates
- Vulnerability scanning

---

## Prioritization Matrix

### Must Have (v2.1)
1. ✅ Delete fork button (DONE)
2. Add new fork from Web UI
3. Auto-start on boot
4. View fork details
5. Disk space monitoring

### Should Have (v2.2)
6. Dark/light theme toggle
7. Fork search/filter
8. Fork switch history
9. Branch switching

### Nice to Have (v2.3+)
10. Update fork from remote
11. Fork comparison
12. Backup/restore
13. Password protection
14. Templates
15. Multi-device sync

### Future Considerations (v3.0+)
16. Clone progress tracking
17. Error handling improvements
18. Rate limiting
19. Logging enhancements
20. WebSocket support
21. Mobile app
22. Desktop app
23. Fork marketplace
24. Analytics
25. Social features

---

## Development Process

### How to Contribute

1. **Pick a feature** from this roadmap
2. **Create a branch**: `git checkout -b feature/add-new-fork`
3. **Implement** the feature
4. **Test thoroughly**
5. **Document** changes
6. **Commit**: `git commit -m "Add fork cloning from Web UI"`
7. **Push**: `git push origin feature/add-new-fork`
8. **Create PR** to `forkswap` branch

### Testing Protocol

For each new feature:
1. Manual testing on device
2. Test with multiple forks
3. Test error cases
4. Test edge cases
5. Performance testing
6. Security review
7. Update test report

### Release Process

1. Update version number
2. Update CHANGELOG.md
3. Create git tag
4. Push to GitHub
5. Deploy to device
6. Announce to users

---

## Success Metrics

### v2.0.0 Achievements ✅
- ✅ 100% test pass rate (9/9)
- ✅ 0 critical bugs
- ✅ Real user adoption confirmed
- ✅ Universal fork compatibility
- ✅ Mobile-responsive design

### v2.1 Goals
- Add 5 new features
- Maintain 0 critical bugs
- 10+ active users
- <100ms API response time
- >95% uptime

### v2.2 Goals
- 10+ features total
- 50+ active users
- Community contributions
- Mobile app prototype

### v3.0 Goals
- Feature-complete Web UI
- 100+ active users
- Mobile app release
- Fork marketplace beta

---

## Questions for User

### Immediate Priorities
1. Which Phase 1 features should we build first?
2. Should we focus on UX or advanced features?
3. Any other must-have features?

### Long-Term Vision
4. Mobile app interest?
5. Community marketplace interest?
6. Should we add social features?

---

## Current Sprint (v2.1) - Week 1

### Planned Features
1. ✅ Delete fork button (COMPLETED)
2. Add new fork from Web UI (NEXT)
3. Auto-start on boot
4. View fork details

### Time Estimates
- Total: 4-5 hours
- Delete button: ✅ 1 hour (DONE)
- Add fork: 2-3 hours
- Auto-start: 30 minutes
- Fork details: 1 hour

---

## Changelog

### v2.0.0 (2025-10-14)
- ✅ Complete Web UI rewrite
- ✅ Fork listing with details
- ✅ One-click fork switching
- ✅ Fork deletion with safety checks
- ✅ Real-time auto-refresh
- ✅ Mobile-responsive design
- ✅ Favicon support
- ✅ Production ready

### v2.0.1 (NEXT)
- 🎯 Add new fork from Web UI
- 🎯 Auto-start on boot
- 🎯 View fork details
- 🎯 Disk space monitoring

---

**Status**: Ready for next feature!
**Current Version**: v2.0.0
**Next Version**: v2.1.0
**Access**: http://192.168.1.110:8080
**Branch**: forkswap
**Production Ready**: ✅ YES
