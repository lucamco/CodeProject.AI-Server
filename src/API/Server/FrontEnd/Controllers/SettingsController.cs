﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

using CodeProject.AI.API.Common;
using CodeProject.AI.SDK.Common;

using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;

namespace CodeProject.AI.API.Server.Frontend.Controllers
{
    /// <summary>
    /// A settings name/value
    /// </summary>
    public class SettingsPair
    {
        /// <summary>
        /// Gets or sets the setting name
        /// </summary>
        public string Name { get; set; } = null!;

        /// <summary>
        /// Gets or sets the value
        /// </summary>
        public string? Value { get; set; } = null;
    }

    /// <summary>
    /// A Dictionary of Dictionaries of settings.
    /// </summary>
    /// <remarks>
    /// The Key in the outer dictionary is the section or module name.
    /// The Key in the inner dictionary is the setting name.
    /// The Value in the inner dictionary is the setting value
    /// </remarks>
    /// <example>
    /// {
    ///     "Global":{
    ///         "USE_CUDA" : "True"
    ///     },
    ///     "Objectdetectionyolo": {
    ///         "CUSTOM_MODELS_DIR" : "C:\\BlueIris\\AI",
    ///         "MODEL_SIZE" : "Large"
    ///     },
    ///     "FaceProcessing": {
    ///         "Activate" : "False"
    ///     }
    /// }
    ///</example>
    public class SettingsDict : Dictionary<string, Dictionary<string, string>>
    { }

    /// <summary>
    /// For updating the settings on the server and modules.
    /// </summary>
    [Route("v1/settings")]
    [ApiController]
    public class SettingsController : ControllerBase
    {
        private readonly IConfiguration _config;
        private readonly ServerOptions  _serverOptions;
        private readonly ModuleRunner   _moduleRunner;
        private readonly string         _storagePath;



        /// <summary>
        /// Constructor
        /// </summary>
        /// <param name="config">The configuration</param>
        /// <param name="serverOptions">The server options</param>
        /// <param name="moduleRunner">The module runner instance</param>
        public SettingsController(IConfiguration config,
                                  IOptions<ServerOptions> serverOptions,
                                  ModuleRunner moduleRunner)
        {
            _config        = config;
            _serverOptions = serverOptions.Value;
            _moduleRunner  = moduleRunner;
            _storagePath   = _config["ApplicationDataDir"] 
                           ?? throw new ApplicationException("ApplicationDataDir is not defined in configuration");
        }

        /// <summary>
        /// Manages requests to add / update a single setting for a specific module.
        /// </summary>
        /// <returns>A Response Object.</returns>
        [HttpPost("{moduleId}", Name = "UpsertSetting")]
        [Produces("application/json")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        public async Task<ResponseBase> UpsertSettingAsync(string moduleId, [FromForm] string name, 
                                                           [FromForm] string value)
        {
            if (string.IsNullOrWhiteSpace(moduleId))
                return new ErrorResponse("No module ID provided");

            // We've been toggling between passing a name/value structure, and passing individual
            // params. This just normalises it and helps us switch between the two modes until we
            // settle on one.
            var settings = new SettingsPair() { Name = name, Value = value };
            if (settings == null || string.IsNullOrWhiteSpace(settings.Name))
               return new ErrorResponse("No setting or setting name provided");

            ModuleConfig? module = _moduleRunner.GetModule(moduleId);
            if (module is null)
                return new ErrorResponse($"No module with ID {moduleId} found");

            // Make the change to the module's settings
            module.UpsertSetting(settings.Name, settings.Value);

            // Restart the module and persist the settings
            bool success = false;
            if (await _moduleRunner.RestartProcess(module))
            {
                var settingStore = new PersistedOverrideSettings(_storagePath);
                var overrideSettings = await settingStore.LoadSettings();

                if (ModuleConfigExtensions.UpsertSettings(overrideSettings, module.ModuleId!,
                                                          settings.Name, settings.Value))
                {
                    success = await settingStore.SaveSettings(overrideSettings);
                }
            }

            return new ResponseBase { success = success };
        }

        /// <summary>
        /// Manages requests to add / update settings for one or more modules.
        /// </summary>
        /// <returns>A Response Object.</returns>
        [HttpPost("", Name = "UpsertSettings")]
        [Produces("application/json")]
        //[Consumes("application/json")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        public async Task<ResponseBase> UpsertSettingsAsync([FromBody] SettingsDict settings)
        {
            if (!settings.Any())
                return new ErrorResponse("No settings provided");

            bool restartSuccess = true;

            // Load up the current persisted settings so we can update and re-save them

            var settingStore = new PersistedOverrideSettings(_storagePath);
            var overrideSettings = await settingStore.LoadSettings();

            // Keep tabs on which modules need to be restarted
            List<string>? moduleIdsToRestart = new();

            foreach (var moduleSetting in settings)
            {
                string moduleId = moduleSetting.Key;

                // Special case
                if (moduleId.EqualsIgnoreCase("Global"))
                {
                    // Update all settings based on what's in the global settings. We'll get back a
                    // list of affected modules that need restarting.
                    Dictionary<string, string> globalSettings = moduleSetting.Value;
                    ModuleCollection modules = _moduleRunner.Modules;
                    moduleIdsToRestart = LegacyParams.UpdateSettings(globalSettings, modules,
                                                                     overrideSettings);

                    continue;
                }

                // Targeting a specific module
                ModuleConfig? module = _moduleRunner.GetModule(moduleId);
                if (module is null)
                    continue;

                foreach (var setting in moduleSetting.Value)
                {
                    // Update each setting value for this module (here and now)
                    module.UpsertSetting(setting.Key, setting.Value);

                    // Add this setting to the persisted override settings (settings will maintain
                    // after server restart)
                    ModuleConfigExtensions.UpsertSettings(overrideSettings, module.ModuleId!,
                                                          setting.Key, setting.Value);
                }

                if (!moduleIdsToRestart.Contains(module.ModuleId!, StringComparer.OrdinalIgnoreCase))
                    moduleIdsToRestart.Add(module.ModuleId!);
            }

            // Restart the modules that were updated
            foreach (string moduleId in moduleIdsToRestart)
            {
                ModuleConfig? module = _moduleRunner.GetModule(moduleId);
                if (module is not null)
                    restartSuccess = await _moduleRunner.RestartProcess(module) && restartSuccess;
            }

            // Only persist these override settings if all modules restarted successfully
            bool success = restartSuccess && await settingStore.SaveSettings(overrideSettings);

            return new ResponseBase { success = success };
        }

        /// <summary>
        /// Returns a list of module settings. A GET request.
        /// </summary>
        /// <param name="moduleId">The name of the module for which to get the settings.</param>
        /// <returns>A list of settings.</returns>
        /// <response code="200">Returns the list of detected object information, if any.</response>
        /// <response code="400"></response>            
        [HttpGet("{moduleId}", Name = "List Settings")]
        [Consumes("multipart/form-data")]
        [Produces("application/json")]
        [ProducesResponseType(StatusCodes.Status200OK)]
        [ProducesResponseType(StatusCodes.Status400BadRequest)]
        public ResponseBase ListSettings(string? moduleId)
        {
            if (string.IsNullOrWhiteSpace(moduleId))
                return new ErrorResponse("No module ID provided");

            ModuleConfig? module = _moduleRunner.GetModule(moduleId);
            if (module is null)
                return new ErrorResponse($"No module found with ID {moduleId}");

            Dictionary<string, string?> processEnvironmentVars = new();
            _serverOptions.AddEnvironmentVariables(processEnvironmentVars);
            module.AddEnvironmentVariables(processEnvironmentVars);

            // Expand the environment variables
            foreach (string key in processEnvironmentVars.Keys)
                processEnvironmentVars[key] = _moduleRunner.ModuleSettings.ExpandOption(processEnvironmentVars[key]);

            var response = new SettingsResponse
            {
                success  = true,
                settings = new
                {
                    activate           = module.Activate ?? false,
                    supportGPU         = module.SupportGPU,
                    parallelism        = module.Parallelism,
                    postStartPauseSecs = module.PostStartPauseSecs
                },
                environmentVariables = processEnvironmentVars
            };

            return response;
        }
    }
}
