/*
This file is part of the SunVox library.
Copyright (C) 2007 - 2024 Alexander Zolotov <nightradio@gmail.com>
WarmPlace.ru

MINIFIED VERSION

License: (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to
deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
IN THE SOFTWARE.
*/

#include "psynth_net.h"
#include "sunvox_engine.h"

// REHORSED MODIFICATION: Use unified logging system
#include "../../../log.h"
#undef LOG_TAG
#define LOG_TAG "PSYNTH_INPUT"

#define MODULE_DATA	psynth_input_data
#define MODULE_HANDLER	psynth_input
#define MODULE_INPUTS	0
#define MODULE_OUTPUTS	2
struct MODULE_DATA
{
    PS_CTYPE   ctl_volume;         // Recording volume (existing)
    PS_CTYPE   ctl_monitor_volume; // NEW: Monitor volume
    PS_CTYPE   ctl_stereo;
    // REHORSED: Secondary output for recording (when monitor volume differs)
    PS_STYPE*  recording_output[MODULE_OUTPUTS];  // Full-volume output for recording
    int        recording_output_allocated;         // Size of allocated buffers
};
PS_RETTYPE MODULE_HANDLER( 
    PSYNTH_MODULE_HANDLER_PARAMETERS
    )
{
    psynth_module* mod;
    MODULE_DATA* data;
    if( mod_num >= 0 )
    {
	mod = &pnet->mods[ mod_num ];
	data = (MODULE_DATA*)mod->data_ptr;
    }
    PS_RETTYPE retval = 0;
    switch( event->command )
    {
	case PS_CMD_GET_DATA_SIZE:
	    retval = sizeof( MODULE_DATA );
	    break;
	case PS_CMD_GET_NAME:
	    retval = (PS_RETTYPE)"Input";
	    break;
	case PS_CMD_GET_INFO:
	    {
                const char* lang = slocale_get_lang();
                while( 1 )
                {
                    if( smem_strstr( lang, "ru_" ) )
                    {
                        retval = (PS_RETTYPE)"Input транслирует сигнал с микрофона или line-in входа";
                        break;
                    }
		    retval = (PS_RETTYPE)"Audio input (from microphone or Line-in)";
                    break;
                }
            }
	    break;
	case PS_CMD_GET_COLOR:
	    retval = (PS_RETTYPE)"#009BFF";
	    break;
	case PS_CMD_GET_INPUTS_NUM: retval = MODULE_INPUTS; break;
	case PS_CMD_GET_OUTPUTS_NUM: retval = MODULE_OUTPUTS; break;
	case PS_CMD_GET_FLAGS: retval = PSYNTH_FLAG_GENERATOR; break;
	case PS_CMD_INIT:
	    {
		psynth_resize_ctls_storage( mod_num, 3, pnet );  // Changed from 2 to 3
		
		// Controller 0: Recording Volume (what goes to file)
		psynth_register_ctl( mod_num, "Recording Volume", "", 0, 1024, 256, 0, &data->ctl_volume, 256, 0, pnet );
		
		// Controller 1: Monitor Volume (what you hear) - NEW
		psynth_register_ctl( mod_num, "Monitor Volume", "", 0, 1024, 0, 0, &data->ctl_monitor_volume, 256, 0, pnet );
		
		// Controller 2: Channels (moved from index 1 to 2)
                int stereo = 0;
#if defined(AUDIOUNIT_INPUT)
                stereo = 1;
#endif
                psynth_register_ctl( mod_num, ps_get_string( STR_PS_CHANNELS ), ps_get_string( STR_PS_MONO_STEREO ), 0, 1, stereo, 1, &data->ctl_stereo, -1, 0, pnet );
		
		sunvox_engine* sv = (sunvox_engine*)pnet->host;
                SUNVOX_SOUND_STREAM_CONTROL( sv, SUNVOX_STREAM_ENABLE_INPUT );
	    }
	    retval = 1;
	    break;
	case PS_CMD_CLEAN:
	    retval = 1;
	    break;
	case PS_CMD_RENDER_REPLACE:
	    if( pnet->in_buf )
	    {
		PS_STYPE** outputs = mod->channels_out;
		int offset = mod->offset;
		int frames = mod->frames;
	        if( data->ctl_volume == 0 ) break;
		if( data->ctl_stereo == 0 )
		{
		    if( psynth_get_number_of_outputs( mod ) != 1 )
		    {
			psynth_set_number_of_outputs( 1, mod_num, pnet );
		    }
		}
		else
		{
		    if( psynth_get_number_of_outputs( mod ) != MODULE_OUTPUTS )
		    {
			psynth_set_number_of_outputs( MODULE_OUTPUTS, mod_num, pnet );
		    }
		}
		
		// REHORSED: New strategy - output BOTH volumes simultaneously
		// Main outputs get monitor volume (for speakers/mixing)
		// Secondary recording_output gets recording volume (for file)
		int monitor_vol = data->ctl_monitor_volume;
		int recording_vol = data->ctl_volume;
		bool need_dual_output = (monitor_vol != recording_vol);
		
		// Allocate recording output buffers if needed
		int outputs_num = psynth_get_number_of_outputs( mod );
		if( need_dual_output )
		{
		    int required_samples = pnet->max_buf_size;
		    if( data->recording_output_allocated < required_samples )
		    {
		        if( data->recording_output[0] ) smem_free( data->recording_output[0] );
		        if( data->recording_output[1] ) smem_free( data->recording_output[1] );
		        data->recording_output[0] = (PS_STYPE*)smem_new( required_samples * sizeof(PS_STYPE) );
		        data->recording_output[1] = (PS_STYPE*)smem_new( required_samples * sizeof(PS_STYPE) );
		        data->recording_output_allocated = required_samples;
		    }
		}
		
		// Process each output channel
		for( int ch = 0; ch < outputs_num; ch++ )
		{
		    PS_STYPE* out = outputs[ ch ] + offset;
		    PS_STYPE* rec_out = need_dual_output ? (data->recording_output[ ch ] + offset) : NULL;
		    
		    if( ch >= pnet->in_buf_channels && ch > 0 )
		    {
			// Copy from previous channel if beyond input channels
			PS_STYPE* prev_out = outputs[ ch - 1 ] + offset;
			for( int i = 0; i < frames; i++ ) out[ i ] = prev_out[ i ];
			if( rec_out )
			{
			    PS_STYPE* prev_rec_out = data->recording_output[ ch - 1 ] + offset;
			    for( int i = 0; i < frames; i++ ) rec_out[ i ] = prev_rec_out[ i ];
			}
			continue;
		    }
		    
		    switch( pnet->in_buf_type )
		    {
		        case sound_buffer_int16:
		        {
			    int16_t* in = (int16_t*)pnet->in_buf;
			    in += offset * pnet->in_buf_channels + ch;
			    
			    if( !need_dual_output )
			    {
			        // Single output mode (monitor == recording)
			        if( monitor_vol == 256 )
			        {
			            for( int i = 0; i < frames; i++ )
			            {
			    	        int v = *in;
				        in += pnet->in_buf_channels;
				        PS_STYPE2 res;
				        PS_INT16_TO_STYPE( res, v );
				        out[ i ] = res;
				    }
			        }
			        else
			        {
			            for( int i = 0; i < frames; i++ )
			            {
			    	        int v = *in;
				        v = ( v * monitor_vol ) / 256;
				        in += pnet->in_buf_channels;
				        PS_STYPE2 res;
				        PS_INT16_TO_STYPE( res, v );
				        out[ i ] = res;
				    }
			        }
			    }
			    else
			    {
			        // Dual output mode (different monitor/recording volumes)
			        for( int i = 0; i < frames; i++ )
			        {
			            int v = *in;
			            in += pnet->in_buf_channels;
			            
			            // Monitor volume → main output (speakers)
			            int v_mon = ( v * monitor_vol ) / 256;
			            PS_STYPE2 res_mon;
			            PS_INT16_TO_STYPE( res_mon, v_mon );
			            out[ i ] = res_mon;
			            
			            // Recording volume → secondary output (file)
			            int v_rec = ( v * recording_vol ) / 256;
			            PS_STYPE2 res_rec;
			            PS_INT16_TO_STYPE( res_rec, v_rec );
			            rec_out[ i ] = res_rec;
			        }
			    }
			}
			break;
		case sound_buffer_float32:
		        {
			    float* in = (float*)pnet->in_buf;
			    in += offset * pnet->in_buf_channels + ch;
			    
			    if( !need_dual_output )
			    {
			        // Single output mode
			        if( monitor_vol == 256 )
			        {
			            for( int i = 0; i < frames; i++ )
			            {
			    	        float fv = *in;
				        in += pnet->in_buf_channels;
#ifdef PS_STYPE_FLOATINGPOINT
				        out[ i ] = fv;
#else
				        out[ i ] = (PS_STYPE)( fv * (float)PS_STYPE_ONE );
#endif
				    }
			        }
			        else
			        {
			            for( int i = 0; i < frames; i++ )
			            {
			    	        float fv = *in;
				        fv = ( fv * monitor_vol ) / 256.0f;
				        in += pnet->in_buf_channels;
#ifdef PS_STYPE_FLOATINGPOINT
				        out[ i ] = fv;
#else
				        out[ i ] = (PS_STYPE)( fv * (float)PS_STYPE_ONE );
#endif
				    }
			        }
			    }
			    else
			    {
			        // Dual output mode
			        for( int i = 0; i < frames; i++ )
			        {
			            float fv = *in;
			            in += pnet->in_buf_channels;
			            
			            // Monitor volume → main output (speakers)
			            float fv_mon = ( fv * monitor_vol ) / 256.0f;
#ifdef PS_STYPE_FLOATINGPOINT
			            out[ i ] = fv_mon;
#else
			            out[ i ] = (PS_STYPE)( fv_mon * (float)PS_STYPE_ONE );
#endif
			            
			            // Recording volume → secondary output (file)
			            float fv_rec = ( fv * recording_vol ) / 256.0f;
#ifdef PS_STYPE_FLOATINGPOINT
			            rec_out[ i ] = fv_rec;
#else
			            rec_out[ i ] = (PS_STYPE)( fv_rec * (float)PS_STYPE_ONE );
#endif
			        }
			    }
			}
			break;
			default:
			    break;
		    }
		} 
		retval = 1;
	    }
	    break;
	case PS_CMD_CLOSE:
	    {
		// REHORSED: Free recording output buffers
		if( data->recording_output[0] ) { smem_free( data->recording_output[0] ); data->recording_output[0] = NULL; }
		if( data->recording_output[1] ) { smem_free( data->recording_output[1] ); data->recording_output[1] = NULL; }
		data->recording_output_allocated = 0;
		
		sunvox_engine* sv = (sunvox_engine*)pnet->host;
        	SUNVOX_SOUND_STREAM_CONTROL( sv, SUNVOX_STREAM_DISABLE_INPUT );
    	    }
	    retval = 1;
	    break;
	default: break;
    }
    return retval;
}
