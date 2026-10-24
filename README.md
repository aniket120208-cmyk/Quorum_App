Quorum

Quorum is a Flutter mobile app that brings team collaboration into one place: video meetings, direct and group chat, communities, organizations with team tasks, a shared calendar, an AI assistant and saved items.

Features

Video meetings

Create a meeting and share its link, or join with a code or link
Lobby with camera and microphone preview, and a waiting room where the host admits guests
In-call chat, participant list, camera switching and a mute-everyone-else sound toggle that only affects your device
Host controls: mute a participant, leave, or end the meeting for everyone
Meeting history saved on the device

Chat

Direct messages and group chats with real-time delivery over Socket.IO
Typing indicators, read receipts and @mentions
Photo, file and camera attachments with upload progress
Edit and delete your own messages
Group admin controls: rename, change the group photo, add and remove members
20,000 character message limit with a counter that appears as you approach it

Communities

Create and join communities through invite links
Channels, posts with attachments, and comment threads
Role-based permissions for members and admins

Organizations

Organizations with teams, team chat and member management
Team tasks and a personal "My tasks" view

Calendar

Events with meeting links you can join in one tap
Upcoming meetings shown on the video call screen

AI assistant

Chat, search, project assistance, quick replies and project updates
History of previous AI conversations

Saved items

Save chat messages, files, chats and community posts
Organize them into colored collections and add personal notes
Opening a saved message jumps straight to it in the chat, and opening a saved post opens that post

Other

Email sign up, sign in, verification and password reset
Notifications with preferences
Profile screen
Tech stack
Area	Packages
Framework	Flutter (Dart)
Networking	dio with a JWT interceptor that refreshes tokens automatically
Real-time	socket_io_client
Video calls	flutter_webrtc
Secure storage	flutter_secure_storage for tokens
Local storage	shared_preferences for meeting history
Media and files	image_picker, file_picker, permission_handler
Sharing and links	share_plus, url_launcher
Project structure
lib/
├── main.dart
├── app_navigator.dart
├── jwt_interceptor.dart
├── token_storage.dart          Secure token storage
├── api/                        Repositories, services and socket clients
├── models/                     Data models
├── assets/                     Images
└── screens/
    ├── sign_in_screen/  sign_up_screen/  verify_email_screen/
    ├── forgot_password_screen/  reset_password_screen/
    ├── home_screen/            Home, calendar and bottom navigation
    ├── video_call_screen/      Meeting lobby, room and history
    ├── chat_screen/            Conversations, chat room and group info
    ├── community_screen/       Communities, posts and comments
    ├── organization_screen/    Organizations, teams, tasks and team chat
    ├── ai_assistant_screen/
    ├── saved_items_screen/
    ├── notification_screen/
    └── profile_screen/