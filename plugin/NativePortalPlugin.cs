using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.Threading;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Threading;
using HarmonyLib;
using Microsoft.Win32;
using AffinityPluginLoader;
using AffinityPluginLoader.Core;

namespace NativePortal
{
    public class NativePortalPlugin : AffinityPlugin
    {
        public const string PluginId = "native_portal";
        private static bool _initialized = false;
        private static bool _queueWatcherStarted = false;
        private static string QUEUE_FILE = @"Z:\tmp\affinity_open_queue.txt";

        public override void OnPatch(Harmony harmony, IPluginContext context)
        {
            Logger.Info("[NativePortal] Initializing NativePortal plugin...");
            try
            {
                var runDialog = typeof(FileDialog).GetMethod("RunDialog", BindingFlags.NonPublic | BindingFlags.Instance);
                if (runDialog != null)
                {
                    var prefix = typeof(NativePortalPlugin).GetMethod("RunDialog_Prefix", BindingFlags.Static | BindingFlags.Public);
                    harmony.Patch(runDialog, prefix: new HarmonyMethod(prefix));
                    Logger.Info("[NativePortal] Hooked FileDialog.RunDialog!");
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] FileDialog hook error: " + ex.Message); }
        }

        public override void OnUiReady(IPluginContext context)
        {
            Logger.Info("[NativePortal] OnUiReady! QueueFile=" + QUEUE_FILE);
            InitOnce();
        }

        public override void OnStartupComplete(IPluginContext context)
        {
            Logger.Info("[NativePortal] OnStartupComplete!");
            InitOnce();
        }

        private static void InitOnce()
        {
            if (_initialized) return;
            _initialized = true;
            StartQueueWatcher();
            var disp = Application.Current != null ? Application.Current.Dispatcher : Dispatcher.CurrentDispatcher;
            disp.BeginInvoke(DispatcherPriority.ApplicationIdle, new Action(() => {
                try { OpenFromQueueAndArgs(); }
                catch (Exception ex) { Logger.Error("[NativePortal] Init open error: " + ex); }
            }));
        }

        private static List<string> ReadAndClearQueue()
        {
            List<string> paths = new List<string>();
            try
            {
                if (!File.Exists(QUEUE_FILE))
                    return paths;
                string content = File.ReadAllText(QUEUE_FILE);
                try { File.Delete(QUEUE_FILE); } catch { }
                foreach (string line in content.Split(new char[]{'\r','\n'}, StringSplitOptions.RemoveEmptyEntries))
                {
                    string p = line.Trim().Trim('"', '\'');
                    if (string.IsNullOrEmpty(p) || paths.Contains(p)) continue;
                    // Dosya gerçekten var mı kontrol et — sahte/eski kayıtları atla
                    if (!File.Exists(p))
                    {
                        Logger.Info("[NativePortal] Dosya bulunamadı, atlandı: " + p);
                        continue;
                    }
                    paths.Add(p);
                }
            }
            catch (Exception ex) { Logger.Error("[NativePortal] ReadQueue error: " + ex.Message); }
            return paths;
        }

        private static void OpenFromQueueAndArgs()
        {
            List<string> paths = ReadAndClearQueue();

            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
            {
                string p = args[i].Trim('"', '\'');
                if (string.IsNullOrEmpty(p) || paths.Contains(p)) continue;
                // Sadece gerçekten var olan dosyaları aç (flag'ler ve sahte yollar atlanır)
                if (File.Exists(p)) paths.Add(p);
            }

            if (paths.Count > 0)
            {
                Logger.Info("[NativePortal] Startup opening " + paths.Count + " files: " + string.Join(", ", paths.ToArray()));
                CallOpenFiles(paths);
            }
            else
            {
                Logger.Info("[NativePortal] No startup files.");
            }
        }

        private static void StartQueueWatcher()
        {
            if (_queueWatcherStarted) return;
            _queueWatcherStarted = true;
            var t = new Thread(() => {
                Logger.Info("[NativePortal] Queue watcher thread running. Watching: " + QUEUE_FILE);
                int tick = 0;
                while (true)
                {
                    try
                    {
                        bool exists = File.Exists(QUEUE_FILE);
                        if (tick % 50 == 0) // log every 5s
                            Logger.Info("[NativePortal] QW tick=" + tick + " exists=" + exists);
                        tick++;

                        if (exists && Application.Current != null)
                        {
                            List<string> paths = ReadAndClearQueue();
                            if (paths.Count > 0)
                            {
                                List<string> cap = paths;
                                Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => {
                                    Logger.Info("[NativePortal] Queue: opening " + string.Join(", ", cap.ToArray()));
                                    CallOpenFiles(cap);
                                }));
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        Logger.Error("[NativePortal] QW error: " + ex.Message);
                    }
                    Thread.Sleep(100);
                }
            });
            t.IsBackground = true;
            t.Name = "NativePortalQueueWatcher";
            t.Start();
            Logger.Info("[NativePortal] Queue watcher started.");
        }

        private static void CallOpenFiles(List<string> paths)
        {
            object app = Application.Current;
            if (app == null) { Logger.Error("[NativePortal] Application.Current is null!"); return; }

            Type appType = app.GetType();
            Logger.Info("[NativePortal] App type: " + appType.FullName);

            // Walk hierarchy to find ProcessCommandLineArguments(IEnumerable<string>)
            Type cursor = appType;
            while (cursor != null && cursor != typeof(object))
            {
                foreach (MethodInfo m in cursor.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
                {
                    if (m.Name == "ProcessCommandLineArguments")
                    {
                        var ps = m.GetParameters();
                        if (ps.Length == 1 && ps[0].ParameterType != typeof(string[]))
                        {
                            Logger.Info("[NativePortal] Found ProcessCommandLineArguments(IEnumerable) on: " + cursor.FullName);
                            try
                            {
                                m.Invoke(app, new object[] { paths });
                                Logger.Info("[NativePortal] ProcessCommandLineArguments SUCCESS!");
                                return;
                            }
                            catch (Exception ex) { Logger.Error("[NativePortal] ProcessCommandLineArguments failed: " + ex); }
                        }
                    }
                }
                cursor = cursor.BaseType;
            }

            // Fallback: LoadFiles (private, but reflection ignores access modifiers)
            cursor = appType;
            while (cursor != null && cursor != typeof(object))
            {
                foreach (MethodInfo m in cursor.GetMethods(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly))
                {
                    if (m.Name == "LoadFiles" && m.GetParameters().Length == 1)
                    {
                        Logger.Info("[NativePortal] Found LoadFiles on: " + cursor.FullName);
                        try
                        {
                            m.Invoke(app, new object[] { paths });
                            Logger.Info("[NativePortal] LoadFiles SUCCESS!");
                            return;
                        }
                        catch (Exception ex) { Logger.Error("[NativePortal] LoadFiles failed: " + ex); }
                    }
                }
                cursor = cursor.BaseType;
            }

            Logger.Error("[NativePortal] No suitable open method found on " + appType.FullName + "!");
        }

        public static bool RunDialog_Prefix(FileDialog __instance, IntPtr hwndOwner, ref bool __result)
        {
            try
            {
                bool isSave = (__instance is SaveFileDialog);
                string mode = isSave ? "save" : "open";
                Logger.Info("[NativePortal] File dialog: " + mode);

                string scriptPath = "/home/ters/.affinity/native_file_chooser.sh";
                string outputFile = @"Z:\tmp\affinity_selected.txt";
                string doneFile = @"Z:\tmp\affinity_done.txt";

                try { if (File.Exists(outputFile)) File.Delete(outputFile); } catch { }
                try { if (File.Exists(doneFile)) File.Delete(doneFile); } catch { }

                string initDir = "";
                try { if (!string.IsNullOrEmpty(__instance.InitialDirectory)) initDir = __instance.InitialDirectory; } catch { }
                if (string.IsNullOrEmpty(initDir))
                    try { if (!string.IsNullOrEmpty(__instance.FileName)) initDir = Path.GetDirectoryName(__instance.FileName); } catch { }

                if (!string.IsNullOrEmpty(initDir))
                {
                    if (initDir.StartsWith("Z:\\", StringComparison.OrdinalIgnoreCase))
                        initDir = initDir.Substring(2).Replace('\\', '/');
                    else if (initDir.StartsWith("C:\\", StringComparison.OrdinalIgnoreCase))
                        initDir = "/home/ters/.affinity/drive_c/" + initDir.Substring(3).Replace('\\', '/');
                }

                var p = new Process();
                p.StartInfo.FileName = "start.exe";
                string args2 = "/unix /bin/bash " + scriptPath + " " + mode;
                if (!string.IsNullOrEmpty(initDir)) args2 += " \"" + initDir + "\"";
                p.StartInfo.Arguments = args2;
                p.StartInfo.UseShellExecute = false;
                p.StartInfo.CreateNoWindow = true;
                p.Start();

                int waited = 0;
                while (!File.Exists(doneFile) && waited < 600000) { Thread.Sleep(50); waited += 50; }
                try { if (File.Exists(doneFile)) File.Delete(doneFile); } catch { }

                if (File.Exists(outputFile))
                {
                    string lp = File.ReadAllText(outputFile).Trim();
                    try { File.Delete(outputFile); } catch { }
                    if (!string.IsNullOrEmpty(lp))
                    {
                        string wp = lp.StartsWith("/") ? @"Z:" + lp.Replace('/', '\\') : lp;
                        if (isSave && !string.IsNullOrEmpty(__instance.DefaultExt) && string.IsNullOrEmpty(Path.GetExtension(wp)))
                        {
                            string ext = __instance.DefaultExt;
                            if (!ext.StartsWith(".")) ext = "." + ext;
                            wp += ext;
                        }
                        Logger.Info("[NativePortal] Selected: " + wp);
                        __instance.FileName = wp;
                        __result = true;
                        return false;
                    }
                }
                __result = false;
                return false;
            }
            catch (Exception ex) { Logger.Error("[NativePortal] RunDialog error: " + ex.Message); return true; }
        }
    }
}
