"""Where the drawings' files live.

The API only talks to `FileStore`. In Azure it is a blob container the
Function App reaches with its managed identity; tests use `MemoryFileStore`.
"""

import os
from collections.abc import Mapping
from functools import lru_cache
from typing import Annotated, Protocol

from azure.core.exceptions import AzureError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import ContainerClient, ContentSettings
from fastapi import Depends, HTTPException, status


class FileNotFound(Exception):
    pass


class StorageUnavailable(Exception):
    """The storage couldn't be reached or refused the request."""


class FileStore(Protocol):
    def upload(
        self,
        name: str,
        data: bytes,
        *,
        content_type: str,
        metadata: Mapping[str, str],
    ) -> None:
        """Stores `data` as `name`, replacing a file of the same name.

        All methods raise `StorageUnavailable` when the storage fails.
        """
        ...

    def download(self, name: str) -> bytes:
        """The contents of `name`; raises `FileNotFound` if there is none."""
        ...

    def delete(self, name: str) -> None:
        """Deletes `name` if it exists."""
        ...


class AzureBlobFileStore:
    """Files as blobs in one container, reached with Microsoft Entra ID.

    Uses the managed identity with `client_id` in Azure, and falls back to
    other credentials such as `az login` when running locally.
    """

    def __init__(self, account_name: str, container_name: str, client_id: str | None):
        self._container = ContainerClient(
            account_url=f"https://{account_name}.blob.core.windows.net",
            container_name=container_name,
            credential=DefaultAzureCredential(managed_identity_client_id=client_id),
        )

    def upload(
        self,
        name: str,
        data: bytes,
        *,
        content_type: str,
        metadata: Mapping[str, str],
    ) -> None:
        try:
            self._container.upload_blob(
                name,
                data,
                overwrite=True,
                metadata=dict(metadata),
                content_settings=ContentSettings(content_type=content_type),
            )
        except AzureError as error:
            raise StorageUnavailable(str(error)) from error

    def download(self, name: str) -> bytes:
        try:
            return self._container.download_blob(name).readall()
        except ResourceNotFoundError as error:
            raise FileNotFound(name) from error
        except AzureError as error:
            raise StorageUnavailable(str(error)) from error

    def delete(self, name: str) -> None:
        try:
            self._container.delete_blob(name)
        except ResourceNotFoundError:
            pass
        except AzureError as error:
            raise StorageUnavailable(str(error)) from error


class MemoryFileStore:
    """Keeps the files in memory, e.g. for tests."""

    def __init__(self) -> None:
        self.files: dict[str, tuple[bytes, str, dict[str, str]]] = {}

    def upload(
        self,
        name: str,
        data: bytes,
        *,
        content_type: str,
        metadata: Mapping[str, str],
    ) -> None:
        self.files[name] = (data, content_type, dict(metadata))

    def download(self, name: str) -> bytes:
        if name not in self.files:
            raise FileNotFound(name)
        return self.files[name][0]

    def delete(self, name: str) -> None:
        self.files.pop(name, None)


@lru_cache
def _azure_file_store(
    account_name: str, container_name: str, client_id: str | None
) -> FileStore:
    return AzureBlobFileStore(account_name, container_name, client_id)


def get_file_store() -> FileStore:
    account_name = os.getenv("STORAGE_ACCOUNT_NAME")
    container_name = os.getenv("STORAGE_CONTAINER_NAME")
    if not account_name or not container_name:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE, detail="Storage is not configured"
        )
    client_id = os.getenv("FUNCTION_APP_CLIENT_ID") or None
    return _azure_file_store(account_name, container_name, client_id)


Files = Annotated[FileStore, Depends(get_file_store)]
