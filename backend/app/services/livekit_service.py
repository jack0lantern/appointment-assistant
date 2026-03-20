"""LiveKit room management and token generation for live therapy sessions."""

import datetime

from livekit.api import (
    AccessToken,
    VideoGrants,
    LiveKitAPI,
    CreateRoomRequest,
    DeleteRoomRequest,
    ListParticipantsRequest,
    RoomCompositeEgressRequest,
    EncodedFileOutput,
    EncodedFileType,
    S3Upload,
    StopEgressRequest,
)

from app.config import settings


class LiveKitService:
    def __init__(self):
        self.api_key = settings.LIVEKIT_API_KEY
        self.api_secret = settings.LIVEKIT_API_SECRET
        self.url = settings.LIVEKIT_URL

    def generate_token(
        self,
        room_name: str,
        participant_identity: str,
        participant_name: str,
        *,
        can_publish: bool = True,
        can_subscribe: bool = True,
    ) -> str:
        """Generate a JWT for a participant to join a LiveKit room."""
        token = (
            AccessToken(self.api_key, self.api_secret)
            .with_identity(participant_identity)
            .with_name(participant_name)
            .with_grants(
                VideoGrants(
                    room_join=True,
                    room=room_name,
                    can_publish=can_publish,
                    can_subscribe=can_subscribe,
                )
            )
            .with_ttl(datetime.timedelta(hours=6))
        )
        return token.to_jwt()

    async def create_room(self, room_name: str) -> dict:
        """Create a LiveKit room. Returns room info."""
        async with LiveKitAPI(self.url, self.api_key, self.api_secret) as api:
            room = await api.room.create_room(
                CreateRoomRequest(
                    name=room_name,
                    empty_timeout=300,  # 5 min empty before auto-close
                    max_participants=2,  # therapy is 1:1
                )
            )
            return {
                "name": room.name,
                "sid": room.sid,
                "created_at": room.creation_time,
            }

    async def close_room(self, room_name: str) -> None:
        """Delete/close a LiveKit room."""
        async with LiveKitAPI(self.url, self.api_key, self.api_secret) as api:
            await api.room.delete_room(DeleteRoomRequest(room=room_name))

    async def list_participants(self, room_name: str) -> list[dict]:
        """List current participants in a room."""
        async with LiveKitAPI(self.url, self.api_key, self.api_secret) as api:
            resp = await api.room.list_participants(
                ListParticipantsRequest(room=room_name)
            )
            return [
                {
                    "identity": p.identity,
                    "name": p.name,
                    "joined_at": p.joined_at,
                    "state": str(p.state),
                }
                for p in resp.participants
            ]

    async def start_recording(self, room_name: str, output_path: str) -> str:
        """Start a composite recording of the room via LiveKit Egress.

        Returns the egress ID for tracking.
        """
        async with LiveKitAPI(self.url, self.api_key, self.api_secret) as api:
            output = EncodedFileOutput(
                file_type=EncodedFileType.MP4,
                filepath=output_path,
                s3=self._s3_upload_config(),
            )
            req = RoomCompositeEgressRequest(
                room_name=room_name,
                file_outputs=[output],
                audio_only=True,  # Audio only for transcript generation
            )
            info = await api.egress.start_room_composite_egress(req)
            return info.egress_id

    async def stop_recording(self, egress_id: str) -> dict:
        """Stop an active recording."""
        async with LiveKitAPI(self.url, self.api_key, self.api_secret) as api:
            info = await api.egress.stop_egress(StopEgressRequest(egress_id=egress_id))
            return {
                "egress_id": info.egress_id,
                "status": str(info.status),
            }

    def _s3_upload_config(self) -> S3Upload:
        """Build S3Upload config for LiveKit Egress."""
        return S3Upload(
            access_key=settings.S3_ACCESS_KEY,
            secret=settings.S3_SECRET_KEY,
            bucket=settings.S3_BUCKET_RECORDINGS,
            region=settings.S3_REGION,
            endpoint=settings.S3_ENDPOINT_URL,
            force_path_style=True,  # Required for MinIO
        )

    @staticmethod
    def make_room_name(session_id: int) -> str:
        """Generate a deterministic room name for a session."""
        return f"session_{session_id}"


livekit_service = LiveKitService()
