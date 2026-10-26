# Quorum

**Work better together.**

Quorum is a Flutter-based team collaboration app that brings communication, meetings, project coordination, and productivity tools together in one place. It helps teams, organizations, and communities collaborate through real-time messaging, video meetings, shared calendars, task management, and AI-powered assistance.

## Features

### Video Meetings

- Create meetings and share meeting links with participants.
- Join meetings using a meeting code or link.
- Preview your camera and microphone in the meeting lobby.
- Waiting room with host-controlled participant admission.
- In-call chat and participant list.
- Camera switching and local audio controls.
- Host controls to mute participants, leave a meeting, or end it for everyone.
- Meeting history stored locally on the device.

### Real-Time Chat

- Direct messaging and group conversations.
- Real-time message delivery using Socket.IO.
- Typing indicators, read receipts, and `@mentions`.
- Send photos, files, and camera attachments.
- Upload progress for media and file attachments.
- Edit and delete your own messages.
- Group administration, including renaming groups, updating group photos, and managing members.
- Support for messages up to 20,000 characters, with a counter displayed as you approach the limit.

### Communities

- Create and join communities through invite links.
- Dedicated channels for community discussions.
- Publish posts with media and file attachments.
- Comment threads for discussions.
- Role-based permissions for community members and administrators.

### Organizations and Teams

- Create and manage organizations.
- Organize members into teams.
- Team chat and member management.
- Team task creation and management.
- Personal **My Tasks** view to track assigned work.

### Shared Calendar

- Create and manage calendar events.
- Schedule meetings, reminders, and deadlines.
- Attach meeting links to calendar events.
- Join scheduled meetings directly from the calendar.
- View upcoming meetings from the video call screen.

### AI Assistant

- AI-powered conversations and assistance.
- Search and project-related assistance.
- Generate quick replies.
- Create project updates.
- Access the history of previous AI conversations.

### Saved Items

- Save chat messages, files, conversations, and community posts.
- Organize saved items into color-coded collections.
- Add personal notes to saved content.
- Navigate directly to the original message from a saved message.
- Open community posts directly from saved items.

### Authentication and Account Management

- Email-based sign-up and sign-in.
- Email verification.
- Password reset and recovery.
- JWT-based authentication.
- Automatic access-token refresh using a JWT interceptor.
- Secure storage of authentication tokens.

### Notifications and Profile

- In-app notifications.
- Notification preference management.
- User profile screen and account management.

## Tech Stack

| Area | Technology |
|---|---|
| Framework | Flutter |
| Programming Language | Dart |
| API Networking | Dio |
| Authentication | JWT access and refresh tokens |
| HTTP Interceptors | Custom JWT interceptor |
| Real-Time Communication | Socket.IO |
| Video and Audio Calls | WebRTC |
| Secure Token Storage | `flutter_secure_storage` |
| Local Storage | `shared_preferences` |
| Image Selection | `image_picker` |
| File Selection | `file_picker` |
| Permissions | `permission_handler` |
| Sharing | `share_plus` |
| External Links | `url_launcher` |

## Project Structure

```text
lib/
├── main.dart
├── app_navigator.dart
├── jwt_interceptor.dart
├── token_storage.dart
│
├── api/
│   ├── API clients
│   ├── Repositories
│   ├── Services
│   └── Socket clients
│
├── models/
│   └── Application and API data models
│
├── assets/
│   └── Images and other static resources
│
└── screens/
    ├── sign_in_screen/
    ├── sign_up_screen/
    ├── verify_email_screen/
    ├── forgot_password_screen/
    ├── reset_password_screen/
    │
    ├── home_screen/
    │   ├── Home dashboard
    │   ├── Calendar
    │   └── Bottom navigation
    │
    ├── video_call_screen/
    │   ├── Meeting lobby
    │   ├── Meeting room
    │   └── Meeting history
    │
    ├── chat_screen/
    │   ├── Conversations
    │   ├── Chat room
    │   └── Group information
    │
    ├── community_screen/
    │   ├── Communities
    │   ├── Posts
    │   └── Comments
    │
    ├── organization_screen/
    │   ├── Organizations
    │   ├── Teams
    │   ├── Tasks
    │   └── Team chat
    │
    ├── ai_assistant_screen/
    ├── saved_items_screen/
    ├── notification_screen/
    └── profile_screen/
```

### Architecture Overview

| Component | Responsibility |
|---|---|
| `main.dart` | Initializes and launches the Flutter application. |
| `app_navigator.dart` | Manages application navigation. |
| `jwt_interceptor.dart` | Handles authentication headers and automatic token refresh. |
| `token_storage.dart` | Manages secure storage of authentication tokens. |
| `api/` | Contains networking services, repositories, and socket clients. |
| `models/` | Defines data models for application entities and API responses. |
| `assets/` | Stores images and other static resources. |
| `screens/` | Organizes the user interface by application feature. |