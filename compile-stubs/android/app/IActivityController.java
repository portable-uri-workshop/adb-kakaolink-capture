/*
 * Copyright (C) 2007 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package android.app;

import android.content.Intent;
import android.os.Binder;
import android.os.IBinder;
import android.os.IInterface;
import android.os.RemoteException;

/**
 * Modified/reimplemented compile-only declaration for the hidden platform interface.
 *
 * This class is deliberately excluded from the output DEX. At runtime,
 * app_process resolves the real implementation from Android's boot class path.
 */
public interface IActivityController extends IInterface {
    boolean activityStarting(Intent intent, String pkg) throws RemoteException;

    boolean activityResuming(String pkg) throws RemoteException;

    boolean appCrashed(
            String processName,
            int pid,
            String shortMsg,
            String longMsg,
            long timeMillis,
            String stackTrace) throws RemoteException;

    int appEarlyNotResponding(String processName, int pid, String annotation)
            throws RemoteException;

    int appNotResponding(String processName, int pid, String processStats)
            throws RemoteException;

    int systemNotResponding(String message) throws RemoteException;

    abstract class Stub extends Binder implements IActivityController {
        @Override
        public IBinder asBinder() {
            return this;
        }
    }
}
